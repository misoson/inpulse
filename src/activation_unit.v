//=============================================================================
// File        : activation_unit.v
// Description : Activation Unit for Gated Convolution (DeepFill v2) based NPU
//               - track_sel = 0 : ReLU        (Feature track)
//               - track_sel = 1 : Sigmoid PLAN (Gate track, Piece-wise Linear Approx.)
//
// Design Notes:
//   - Fixed-point format : Q(DATA_WIDTH-FRAC_WIDTH).FRAC_WIDTH, signed 2's complement
//     (Default: Q8.8 -> 16bit total, 8bit integer(incl. sign), 8bit fraction)
//   - No multiplier / divider used. Only Adder, Mux, Shifter (Synthesis-friendly)
//   - 1-stage output pipeline register inserted to cut the critical path
//=============================================================================

module activation_unit #(
    parameter DATA_WIDTH = 16,   // Total bit-width of data (signed)
    parameter FRAC_WIDTH = 8     // Fractional bit-width (Q format)
)(
    input  wire                    clk,
    input  wire                    reset_n,    // Active-low async reset
    input  wire                    enable,     // Module enable

    input  wire                    track_sel,  // 0: ReLU(Feature) / 1: Sigmoid(Gate)
    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire                    valid_in,

    output reg  signed [DATA_WIDTH-1:0] data_out,
    output reg                     valid_out
);

    //-------------------------------------------------------------------
    // Local Parameters : Fixed-point constants derived from FRAC_WIDTH
    //-------------------------------------------------------------------
    // Sigmoid PLAN breakpoints : x = -4.0, x = +4.0 in Q format
    localparam signed [DATA_WIDTH-1:0] NEG_THRESHOLD = -(32'sd4 <<< FRAC_WIDTH); // -4.0
    localparam signed [DATA_WIDTH-1:0] POS_THRESHOLD =  (32'sd4 <<< FRAC_WIDTH); //  4.0

    // Output saturation constants
    localparam signed [DATA_WIDTH-1:0] FP_ZERO = {DATA_WIDTH{1'b0}};            //  0.0
    localparam signed [DATA_WIDTH-1:0] FP_ONE  =  (32'sd1 <<< FRAC_WIDTH);      //  1.0
    localparam signed [DATA_WIDTH-1:0] FP_HALF =  (32'sd1 <<< (FRAC_WIDTH-1));  //  0.5

    //-------------------------------------------------------------------
    // Stage 0 (Combinational) : Activation Function Computation
    //-------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] relu_result;
    reg signed [DATA_WIDTH-1:0] sigmoid_result;
    reg signed [DATA_WIDTH-1:0] act_result_comb;

    // Intermediate wire for PLAN linear segment: (x >> 3) + 0.5
    // Using arithmetic shift (>>>) on signed data to preserve sign (no multiplier/divider)
    wire signed [DATA_WIDTH-1:0] shifted_x;
    assign shifted_x = data_in >>> 3; // equivalent to x / 8, hardware-friendly (single shifter)

    //--------------------------------------
    // ReLU (track_sel == 0)
    //--------------------------------------
    always @(*) begin
        // Check MSB (sign bit) only -> negative number => 0, else pass-through
        if (data_in[DATA_WIDTH-1] == 1'b1)
            relu_result = FP_ZERO;
        else
            relu_result = data_in;
    end

    //--------------------------------------
    // Sigmoid PLAN (track_sel == 1)
    // x <  -4        -> 0
    // -4 <= x < 4     -> (x >> 3) + 0.5
    // x >=  4        -> 1
    //--------------------------------------
    always @(*) begin
        if (data_in < NEG_THRESHOLD)
            sigmoid_result = FP_ZERO;
        else if (data_in >= POS_THRESHOLD)
            sigmoid_result = FP_ONE;
        else
            sigmoid_result = shifted_x + FP_HALF; // Adder + Shifter only
    end

    //--------------------------------------
    // Track Selection MUX
    //--------------------------------------
    always @(*) begin
        case (track_sel)
            1'b0:    act_result_comb = relu_result;     // Feature track
            1'b1:    act_result_comb = sigmoid_result;   // Gate track
            default: act_result_comb = relu_result;
        endcase
    end

    //-------------------------------------------------------------------
    // Stage 1 (Sequential) : Output Pipeline Register
    // - Cuts critical path between combinational activation logic
    //   and the next stage (Pipeline Matcher)
    // - Async active-low reset
    //-------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out  <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end
        else if (enable) begin
            data_out  <= act_result_comb;
            valid_out <= valid_in;
        end
        else begin
            // When disabled, hold output value but drop valid to avoid
            // downstream misinterpretation of stale data
            valid_out <= 1'b0;
        end
    end

endmodule
