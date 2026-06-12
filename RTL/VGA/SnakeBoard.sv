// ===========================================================================
// SnakeBoard  (Slimming Snake project, Spring 2026)            STEP 6
// ---------------------------------------------------------------------------
// The whole game lives here.  It draws and runs a 20 x 15 grid of 32x32 px
// tiles that fills the screen (20*32 = 640, 15*32 = 480).
//
// (Formerly "HartsMatrixBitMap" - the heart-matrix block from the skeleton.
//  Same module footprint, repurposed into the snake board.)
//
// Data model:
//   * snakeCol[i]/snakeRow[i] + snakeLen : the ordered body, as a shift
//     register.  index 0 = head; movement shifts every cell into the place of
//     the cell in front of it and advances the head one tile.
//   * foodGrid  : apple / cake cells, kept SEPARATE from the snake so the
//     snake gliding over food does not erase it.
//   * snakeGrid : head / body marker per cell, for O(1) render & collision.
//
// Control: 8 = up, 2 = down, 4 = left, 6 = right; 180-degree turns rejected.
//
// Food: ONE apple (eat -> score +1, snake SLIMS, new apple at a random free
//       cell via LFSR); cakes start at one and slowly accumulate (eat -> GROW).
//
// STEP 6 additions:
//   * SPEED-UP: the step interval shrinks a little with every apple eaten, so
//     the snake gradually gets faster (down to a floor).
//   * WIN: slimming down to the minimum length wins the game.
//   * TWO-DIGIT score on the `score[7:0]` output ({tens, ones}).
//   * soundSelect[3:0] tells the audio block which of 4 sounds to play:
//       1 = apple, 2 = cake, 3 = die, 4 = win   (0 = silent).
//
// Game FSM: INIT -> PLAY -> {OVER | WIN} -> auto-restart.
//
// (c) Technion IIT, Department of Electrical Engineering 2026
// ===========================================================================

module	SnakeBoard	(
					input	logic	clk,
					input	logic	resetN,
					input	logic	[10:0] pixelX,           // current scan pixel X (screen coordinate)
					input	logic	[10:0] pixelY,           // current scan pixel Y (screen coordinate)
					input	logic	insideBoard,            // high while the pixel is inside the board area
					input	logic	unusedRandom,           // legacy skeleton port, not used
					input	logic	unusedCollision,        // legacy skeleton port, not used
					input	logic	[3:0] dirKey,           // last number key (8/2/4/6 steer the snake)

					output	logic	[7:0] score,            // {tens[7:4], ones[3:0]} for the display
					output	logic	[3:0] soundSelect,      // melody index for the AUDIO block (per event)
					output	logic	soundTrigger,           // short pulse = "start that melody"
					output	logic	drawingRequest,         // high = this pixel is ours (opaque)
					output	logic	[7:0] RGBout            // tile color for this pixel
 ) ;

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;

// ---- board geometry --------------------------------------------------------
localparam int TILE_BITS = 5 ;   // 32 px tile = 2^5, so a tile index = pixel >> 5
localparam int NUM_COLS  = 20 ;
localparam int NUM_ROWS  = 15 ;

// ---- snake sizing ----------------------------------------------------------
localparam int MAX_LEN   = 40 ;
localparam int INIT_LEN  = 8  ;
localparam int MIN_LEN   = 2  ; // slimming down to here = WIN

// ---- timing (clk = 31.5 MHz pixel clock) -----------------------------------
localparam int TICK_BASE        = 6_000_000   ; // ~5 steps/s at the start
localparam int TICK_STEP        = 400_000     ; // faster by this much per apple
localparam int TICK_MIN         = 1_500_000   ; // speed floor (~21 steps/s)
localparam int RESTART_DELAY    = 45_000_000  ; // ~1.5 s frozen on game over
localparam int WIN_HOLD         = 90_000_000  ; // ~3 s win screen
localparam int CAKE_SPAWN_DELAY = 200_000_000 ; // ~6.3 s between new cakes
localparam int MAX_CAKES        = 6           ;
localparam int TRIG_WIDTH       = 4096        ; // start-melody pulse width (~0.13 ms)

// ---- encodings -------------------------------------------------------------
localparam logic [1:0] F_EMPTY = 2'd0, F_APPLE = 2'd1, F_CAKE = 2'd2 ;
localparam logic [1:0] S_EMPTY = 2'd0, S_HEAD  = 2'd1, S_BODY = 2'd2 ;
localparam logic [1:0] DIR_RIGHT = 2'd0, DIR_DOWN = 2'd1, DIR_LEFT = 2'd2, DIR_UP = 2'd3 ;
localparam logic [1:0] ST_INIT = 2'd0, ST_PLAY = 2'd1, ST_OVER = 2'd2, ST_WIN = 2'd3 ;
// melody indices into songs.mif (any 4 distinct songs give 4 distinct sounds)
localparam logic [3:0] MEL_APPLE = 4'd1, MEL_CAKE = 4'd2, MEL_DIE = 4'd3, MEL_WIN = 4'd4 ;

// ---- tile colors: RED = bits[7:5], GREEN = bits[4:2], BLUE = bits[1:0] ------
localparam logic [7:0] COLOR_APPLE = 8'hE0 ; // red
localparam logic [7:0] COLOR_CAKE  = 8'hE3 ; // magenta
localparam logic [7:0] COLOR_HEAD  = 8'hFC ; // yellow
localparam logic [7:0] COLOR_BODY  = 8'h1C ; // green
localparam logic [7:0] COLOR_DEAD  = 8'h92 ; // gray  (crashed snake)
localparam logic [7:0] COLOR_WIN   = 8'h1F ; // cyan  (winning snake)

// ---- state -----------------------------------------------------------------
logic [1:0]  foodGrid  [0:NUM_ROWS-1][0:NUM_COLS-1] ; // apple / cake per cell
logic [1:0]  snakeGrid [0:NUM_ROWS-1][0:NUM_COLS-1] ; // head / body per cell
logic [4:0]  snakeCol  [0:MAX_LEN-1] ;                // body column list (0 = head)
logic [3:0]  snakeRow  [0:MAX_LEN-1] ;                // body row list    (0 = head)
logic [5:0]  snakeLen ;
logic [1:0]  curDir ;
logic [1:0]  gameState ;
logic [3:0]  scoreOnes, scoreTens ;
logic [22:0] tickCnt ;
logic [22:0] tickThreshold ;     // current step interval (shrinks as you eat apples)
logic [26:0] freezeCnt ;         // game-over / win freeze timer
logic [27:0] cakeSpawnCnt ;
logic [3:0]  cakeCount ;
logic        applePending, cakeSpawnPending ;
logic [15:0] lfsr ;
logic [12:0] soundPulseCnt ;

assign score = {scoreTens, scoreOnes} ;

// ---- which tile does the current pixel fall in -----------------------------
logic [4:0] tileCol ;
logic [3:0] tileRow ;
assign tileCol = pixelX[TILE_BITS+4 : TILE_BITS] ;
assign tileRow = pixelY[TILE_BITS+3 : TILE_BITS] ;

// ---- keypad -> requested direction (with anti-reverse) ---------------------
logic [1:0] keyDir ;
logic       keyIsDir ;
always_comb begin
	keyIsDir = 1'b1 ;
	unique case (dirKey)
		4'd8    : keyDir = DIR_UP ;
		4'd2    : keyDir = DIR_DOWN ;
		4'd4    : keyDir = DIR_LEFT ;
		4'd6    : keyDir = DIR_RIGHT ;
		default : begin keyDir = curDir ; keyIsDir = 1'b0 ; end
	endcase
end
logic wouldReverse ;
always_comb begin
	wouldReverse = (keyDir == DIR_UP    && curDir == DIR_DOWN ) ||
	               (keyDir == DIR_DOWN  && curDir == DIR_UP   ) ||
	               (keyDir == DIR_LEFT  && curDir == DIR_RIGHT) ||
	               (keyDir == DIR_RIGHT && curDir == DIR_LEFT ) ;
end
logic [1:0] nextDir ;
assign nextDir = (keyIsDir && !wouldReverse) ? keyDir : curDir ;

// ---- next head cell + collisions -------------------------------------------
logic [4:0] headNextCol ;
logic [3:0] headNextRow ;
logic       wallHit, selfHit, collision ;
always_comb begin
	headNextCol = snakeCol[0] ;
	headNextRow = snakeRow[0] ;
	unique case (nextDir)
		DIR_RIGHT : headNextCol = (snakeCol[0] == NUM_COLS-1) ? snakeCol[0] : snakeCol[0] + 5'd1 ;
		DIR_LEFT  : headNextCol = (snakeCol[0] == 5'd0)       ? snakeCol[0] : snakeCol[0] - 5'd1 ;
		DIR_DOWN  : headNextRow = (snakeRow[0] == NUM_ROWS-1) ? snakeRow[0] : snakeRow[0] + 4'd1 ;
		DIR_UP    : headNextRow = (snakeRow[0] == 4'd0)       ? snakeRow[0] : snakeRow[0] - 4'd1 ;
	endcase
end
always_comb begin
	wallHit = (nextDir == DIR_RIGHT && snakeCol[0] == NUM_COLS-1) ||
	          (nextDir == DIR_LEFT  && snakeCol[0] == 5'd0)       ||
	          (nextDir == DIR_DOWN  && snakeRow[0] == NUM_ROWS-1) ||
	          (nextDir == DIR_UP    && snakeRow[0] == 4'd0)       ;
	selfHit = !wallHit &&
	          (snakeGrid[headNextRow][headNextCol] == S_BODY) &&
	          !(headNextCol == snakeCol[snakeLen-1] && headNextRow == snakeRow[snakeLen-1]) ;
	collision = wallHit || selfHit ;
end

logic eatApple, eatCake ;
assign eatApple = (foodGrid[headNextRow][headNextCol] == F_APPLE) ;
assign eatCake  = (foodGrid[headNextRow][headNextCol] == F_CAKE) ;

// ---- event pulses (combinational, true for the one movement clock) ---------
logic tickNow, appleEatNow, cakeEatNow, dieNow, winNow ;
assign tickNow     = (gameState == ST_PLAY) && (tickCnt >= tickThreshold - 23'd1) ;
assign appleEatNow = tickNow && !collision && eatApple ;
assign cakeEatNow  = tickNow && !collision && eatCake ;
assign dieNow      = tickNow && collision ;
assign winNow      = appleEatNow && (snakeLen == 6'(MIN_LEN + 1)) ; // this apple reaches the minimum

// ---- random free cell from the LFSR ----------------------------------------
logic [4:0] randCol, randColSafe ;
logic [3:0] randRow, randRowSafe ;
logic       cellIsFree ;
assign randCol     = lfsr[4:0] ;
assign randRow     = lfsr[11:8] ;
assign randColSafe = (randCol < NUM_COLS) ? randCol : 5'd0 ;
assign randRowSafe = (randRow < NUM_ROWS) ? randRow : 4'd0 ;
assign cellIsFree  = (randCol < NUM_COLS) && (randRow < NUM_ROWS) &&
                     (snakeGrid[randRowSafe][randColSafe] == S_EMPTY) &&
                     (foodGrid [randRowSafe][randColSafe] == F_EMPTY) ;

// ===========================================================================
// Game update
// ===========================================================================
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		gameState <= ST_INIT ;
		tickCnt   <= 23'd0 ;
		freezeCnt <= 27'd0 ;
		curDir    <= DIR_RIGHT ;
		lfsr          <= 16'hACE1 ;
		soundSelect   <= 4'd0 ;
		soundTrigger  <= 1'b0 ;
		soundPulseCnt <= 13'd0 ;
	end
	else begin
		lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]} ;

		// ---- pick the melody on an event and emit a short start pulse -------
		// soundSelect is HELD (changes only on a new event) so it stays stable
		// while the chosen melody plays; soundTrigger is a short start pulse.
		if      (winNow)      begin soundSelect <= MEL_WIN ;   soundTrigger <= 1'b1 ; soundPulseCnt <= 13'(TRIG_WIDTH) ; end
		else if (dieNow)      begin soundSelect <= MEL_DIE ;   soundTrigger <= 1'b1 ; soundPulseCnt <= 13'(TRIG_WIDTH) ; end
		else if (appleEatNow) begin soundSelect <= MEL_APPLE ; soundTrigger <= 1'b1 ; soundPulseCnt <= 13'(TRIG_WIDTH) ; end
		else if (cakeEatNow)  begin soundSelect <= MEL_CAKE ;  soundTrigger <= 1'b1 ; soundPulseCnt <= 13'(TRIG_WIDTH) ; end
		else if (soundPulseCnt != 13'd0) soundPulseCnt <= soundPulseCnt - 13'd1 ;
		else soundTrigger <= 1'b0 ;

		case (gameState)

		// -- load the starting board ----------------------------------------
		ST_INIT : begin
			tickCnt          <= 23'd0 ;
			freezeCnt        <= 27'd0 ;
			cakeSpawnCnt     <= 28'd0 ;
			curDir           <= DIR_RIGHT ;
			snakeLen         <= 6'(INIT_LEN) ;
			tickThreshold    <= 23'(TICK_BASE) ;
			scoreOnes        <= 4'd0 ;
			scoreTens        <= 4'd0 ;
			cakeCount        <= 4'd1 ;
			applePending     <= 1'b0 ;
			cakeSpawnPending <= 1'b0 ;

			for (int rr = 0 ; rr < NUM_ROWS ; rr++)
				for (int cc = 0 ; cc < NUM_COLS ; cc++) begin
					foodGrid[rr][cc]  <= F_EMPTY ;
					snakeGrid[rr][cc] <= S_EMPTY ;
				end
			foodGrid[5][15] <= F_APPLE ;
			foodGrid[10][5] <= F_CAKE  ;
			for (int i = 0 ; i < MAX_LEN ; i++) begin
				snakeCol[i] <= (i < INIT_LEN) ? 5'(10 - i) : 5'd3 ;
				snakeRow[i] <= 4'd7 ;
			end
			for (int i = 0 ; i < INIT_LEN ; i++)
				snakeGrid[7][10 - i] <= (i == 0) ? S_HEAD : S_BODY ;

			gameState <= ST_PLAY ;
		end

		// -- play -----------------------------------------------------------
		ST_PLAY : begin
			if (cakeSpawnCnt >= CAKE_SPAWN_DELAY) begin
				cakeSpawnCnt <= 28'd0 ;
				if (cakeCount < MAX_CAKES) cakeSpawnPending <= 1'b1 ;
			end
			else cakeSpawnCnt <= cakeSpawnCnt + 28'd1 ;

			if (tickNow) begin
				tickCnt <= 23'd0 ;
				if (collision) begin
					gameState <= ST_OVER ;
					freezeCnt <= 27'd0 ;
				end
				else begin
					curDir <= nextDir ;

					if (eatApple) begin
						foodGrid[headNextRow][headNextCol] <= F_EMPTY ;
						applePending <= 1'b1 ;
						// two-digit score++
						if (scoreOnes == 4'd9) begin
							scoreOnes <= 4'd0 ;
							if (scoreTens < 4'd9) scoreTens <= scoreTens + 4'd1 ;
						end
						else scoreOnes <= scoreOnes + 4'd1 ;
						// gradual speed-up
						if (tickThreshold > 23'(TICK_MIN + TICK_STEP))
							tickThreshold <= tickThreshold - 23'(TICK_STEP) ;
						else
							tickThreshold <= 23'(TICK_MIN) ;
					end
					else if (eatCake) begin
						foodGrid[headNextRow][headNextCol] <= F_EMPTY ;
						cakeCount <= cakeCount - 4'd1 ;
					end

					// old head -> body
					snakeGrid[snakeRow[0]][snakeCol[0]] <= S_BODY ;
					// shift the body
					for (int i = MAX_LEN-1 ; i > 0 ; i--) begin
						snakeCol[i] <= snakeCol[i-1] ;
						snakeRow[i] <= snakeRow[i-1] ;
					end
					snakeCol[0] <= headNextCol ;
					snakeRow[0] <= headNextRow ;

					// tail handling depends on what was eaten
					if (eatCake && snakeLen < MAX_LEN) begin
						snakeLen <= snakeLen + 6'd1 ;                       // grow
					end
					else if (eatApple && snakeLen > MIN_LEN) begin
						snakeLen <= snakeLen - 6'd1 ;                       // slim
						snakeGrid[snakeRow[snakeLen-1]][snakeCol[snakeLen-1]] <= S_EMPTY ;
						snakeGrid[snakeRow[snakeLen-2]][snakeCol[snakeLen-2]] <= S_EMPTY ;
						if (snakeLen == 6'(MIN_LEN + 1)) begin            // reached minimum -> WIN
							gameState <= ST_WIN ;
							freezeCnt <= 27'd0 ;
						end
					end
					else begin
						snakeGrid[snakeRow[snakeLen-1]][snakeCol[snakeLen-1]] <= S_EMPTY ;
					end

					snakeGrid[headNextRow][headNextCol] <= S_HEAD ; // wins any overlap
				end
			end
			else begin
				tickCnt <= tickCnt + 23'd1 ;
				// resolve random food placement between steps
				if (applePending && cellIsFree) begin
					foodGrid[randRowSafe][randColSafe] <= F_APPLE ;
					applePending <= 1'b0 ;
				end
				else if (cakeSpawnPending && cellIsFree) begin
					foodGrid[randRowSafe][randColSafe] <= F_CAKE ;
					cakeCount        <= cakeCount + 4'd1 ;
					cakeSpawnPending <= 1'b0 ;
				end
			end
		end

		// -- game over (gray) -----------------------------------------------
		ST_OVER : begin
			if (freezeCnt >= RESTART_DELAY) gameState <= ST_INIT ;
			else                            freezeCnt <= freezeCnt + 27'd1 ;
		end

		// -- win (cyan) -----------------------------------------------------
		ST_WIN : begin
			if (freezeCnt >= WIN_HOLD) gameState <= ST_INIT ;
			else                       freezeCnt <= freezeCnt + 27'd1 ;
		end

		default : gameState <= ST_INIT ;
		endcase
	end
end

// ===========================================================================
// Render
// ===========================================================================
logic [7:0] snakeColor ;
always_comb begin
	unique case (gameState)
		ST_OVER : snakeColor = COLOR_DEAD ;
		ST_WIN  : snakeColor = COLOR_WIN ;
		default : snakeColor = COLOR_BODY ;
	endcase
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		RGBout <= 8'h00 ;
	end
	else begin
		RGBout <= TRANSPARENT_ENCODING ;
		if (insideBoard) begin
			if      (snakeGrid[tileRow][tileCol] == S_HEAD)
				RGBout <= (gameState == ST_PLAY || gameState == ST_INIT) ? COLOR_HEAD : snakeColor ;
			else if (snakeGrid[tileRow][tileCol] == S_BODY)
				RGBout <= snakeColor ;
			else if (foodGrid [tileRow][tileCol] == F_APPLE) RGBout <= COLOR_APPLE ;
			else if (foodGrid [tileRow][tileCol] == F_CAKE)  RGBout <= COLOR_CAKE ;
			else                                             RGBout <= TRANSPARENT_ENCODING ;
		end
	end
end

assign drawingRequest = (RGBout != TRANSPARENT_ENCODING) ? 1'b1 : 1'b0 ;

endmodule
