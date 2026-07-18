`timescale 1ns / 1ps

module npu_axi_ip_v1_0_S00_AXI # (
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6     // 16개 레지스터 지원
) (
    input  wire  S_AXI_ACLK,
    input  wire  S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input  wire [2 : 0] S_AXI_AWPROT,
    input  wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input  wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input  wire  S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input  wire [2 : 0] S_AXI_ARPROT,
    input  wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input  wire  S_AXI_RREADY
);

    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg  axi_awready;
    reg  axi_wready;
    reg [1 : 0] axi_bresp;
    reg  axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg  axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1 : 0] axi_rresp;
    reg  axi_rvalid;

    localparam ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    
    // 16개의 32비트 기본 레지스터 정의
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0; // Control (start, is_deep)
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1; // Weight Addr / Target
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2; // Weight Data
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3; // Pixel Data In
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg4; 
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg5, slv_reg6, slv_reg7, slv_reg8;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg9, slv_reg10, slv_reg11, slv_reg12;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg13, slv_reg14, slv_reg15;

    wire slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_awready <= 1'b0;
            axi_awaddr  <= 0;
        end else begin    
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= S_AXI_AWADDR;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_wready <= 1'b0;
        end else begin    
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end
    end

    integer byte_index;
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            slv_reg0 <= 0; slv_reg1 <= 0; slv_reg2 <= 0; slv_reg3 <= 0;
            slv_reg4 <= 0; slv_reg5 <= 0; slv_reg6 <= 0; slv_reg7 <= 0;
            slv_reg8 <= 0; slv_reg9 <= 0; slv_reg10<= 0; slv_reg11<= 0;
            slv_reg12<= 0; slv_reg13<= 0; slv_reg14<= 0; slv_reg15<= 0;
        end else begin
            if (npu_layer_done) begin
                slv_reg0[0] <= 1'b0; // 연산 완료 시 start 자동 클리어
            end
            
            if (slv_reg_wren) begin
                case ( axi_awaddr[C_S_AXI_ADDR_WIDTH-1 : ADDR_LSB] )
                    4'h0: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    4'h1: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    4'h2: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    4'h3: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    default : ;
                endcase
            end
        end
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b00;
        end else begin    
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00;
            end else begin
                if (S_AXI_BREADY && axi_bvalid) begin
                    axi_bvalid <= 1'b0;
                end  
            end
        end
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 32'b0;
        end else begin    
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin    
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    always @(*) begin
        case ( axi_araddr[C_S_AXI_ADDR_WIDTH-1 : ADDR_LSB] )
            4'h0   : reg_data_out <= {30'd0, npu_layer_done, slv_reg0[0]}; 
            4'h1   : reg_data_out <= slv_reg1;
            4'h2   : reg_data_out <= slv_reg2;
            4'h3   : reg_data_out <= slv_reg3;
            4'h4   : reg_data_out <= out_ch0_buf; 
            default : reg_data_out <= 0;
        endcase
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_rdata  <= 0;
        end else begin    
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rdata <= reg_data_out;
            end
        end
    end

    //--------------------------------------------------------------------------
    // NPU Core 아키텍처 인스턴스화 통합 파트 (최신 업데이트 반영)
    //--------------------------------------------------------------------------
    wire         npu_layer_done;
    wire [15:0]  npu_out_data;
    wire [1:0]   npu_out_ch_sel;
    wire         npu_output_valid;

    wire npu_weight_wr_en     = slv_reg_wren && (axi_awaddr[C_S_AXI_ADDR_WIDTH-1 : ADDR_LSB] == 4'h2);
    wire npu_photo_data_valid = slv_reg_wren && (axi_awaddr[C_S_AXI_ADDR_WIDTH-1 : ADDR_LSB] == 4'h3);

    npu_top #(
        .DATA_WIDTH(8),
        .LINE_LENGTH(1024),
        .ACT_DATA_WIDTH(16),
        .FRAC_WIDTH(8)        // 👈 팀원들의 전력/면적 최적화 파라미터 결합 완료!
    ) u_npu_top (
        .clk              (S_AXI_ACLK),
        .reset            (!S_AXI_ARESETN),
        
        .layer_start      (slv_reg0[0]),
        .layer_is_deep    (slv_reg0[1]), 
        .layer_out_pixels (slv_reg0[31:16]), 
        .layer_done       (npu_layer_done),
        
        .photo_data_valid (npu_photo_data_valid),
        .pixel_data_in    (slv_reg3[7:0]),
        
        .weight_wr_en     (npu_weight_wr_en),
        .weight_wr_target (slv_reg1[4]),   
        .weight_wr_addr   (slv_reg1[3:0]), 
        .weight_wr_data   (slv_reg2),      
        
        .out_data          (npu_out_data),
        .out_ch_sel        (npu_out_ch_sel),
        .output_valid      (npu_output_valid)
    );

    reg [31:0] out_ch0_buf;
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            out_ch0_buf <= 32'd0;
        end else if (npu_output_valid && (npu_out_ch_sel == 2'd0)) begin
            out_ch0_buf <= {{16{npu_out_data[15]}}, npu_out_data};
        end
    end

endmodule