`timescale 1ns/1ps
module axi_lite_regs (
    input wire ACLK, ARESETn,
    input wire [7:0] S_AXI_AWADDR, input wire S_AXI_AWVALID, output wire S_AXI_AWREADY,
    input wire [31:0] S_AXI_WDATA, input wire [3:0] S_AXI_WSTRB,
    input wire S_AXI_WVALID, output wire S_AXI_WREADY,
    output reg [1:0] S_AXI_BRESP, output reg S_AXI_BVALID, input wire S_AXI_BREADY,
    input wire [7:0] S_AXI_ARADDR, input wire S_AXI_ARVALID, output wire S_AXI_ARREADY,
    output reg [31:0] S_AXI_RDATA, output reg [1:0] S_AXI_RRESP,
    output reg S_AXI_RVALID, input wire S_AXI_RREADY
);
    reg [31:0] control_reg, data_reg;
    reg [7:0] awaddr_buf;
    reg [31:0] wdata_buf;
    reg [3:0] wstrb_buf;
    reg aw_pending, w_pending;
    integer k;
    reg [31:0] masked_value;

    // One outstanding write. AW and W may arrive in either order.
    assign S_AXI_AWREADY = !aw_pending && !S_AXI_BVALID;
    assign S_AXI_WREADY  = !w_pending  && !S_AXI_BVALID;
    // One outstanding read.
    assign S_AXI_ARREADY = !S_AXI_RVALID;

    always @(posedge ACLK) begin
        if (!ARESETn) begin
            control_reg <= 0; data_reg <= 0;
            awaddr_buf <= 0; wdata_buf <= 0; wstrb_buf <= 0;
            aw_pending <= 0; w_pending <= 0;
            S_AXI_BVALID <= 0; S_AXI_BRESP <= 0;
            S_AXI_RVALID <= 0; S_AXI_RRESP <= 0; S_AXI_RDATA <= 0;
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                awaddr_buf <= S_AXI_AWADDR;
                aw_pending <= 1;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                wdata_buf <= S_AXI_WDATA;
                wstrb_buf <= S_AXI_WSTRB;
                w_pending <= 1;
            end
            if (aw_pending && w_pending && !S_AXI_BVALID) begin
                S_AXI_BVALID <= 1;
                S_AXI_BRESP <= 2'b00; // OKAY, including writes to reserved addresses
                case (awaddr_buf)
                    8'h00: for (k=0; k<4; k=k+1)
                        if (wstrb_buf[k]) control_reg[k*8 +: 8] <= wdata_buf[k*8 +: 8];
                    8'h08: for (k=0; k<4; k=k+1)
                        if (wstrb_buf[k]) data_reg[k*8 +: 8] <= wdata_buf[k*8 +: 8];
                    default: ; // STATUS is read-only; reserved addresses ignored
                endcase
                aw_pending <= 0;
                w_pending <= 0;
            end
            if (S_AXI_BVALID && S_AXI_BREADY) S_AXI_BVALID <= 0;

            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                S_AXI_RVALID <= 1;
                S_AXI_RRESP <= 2'b00;
                case (S_AXI_ARADDR)
                    8'h00: S_AXI_RDATA <= control_reg;
                    8'h04: S_AXI_RDATA <= 32'h0000_0001; // mock status: ready
                    8'h08: S_AXI_RDATA <= data_reg;
                    default: S_AXI_RDATA <= 0;
                endcase
            end
            if (S_AXI_RVALID && S_AXI_RREADY) S_AXI_RVALID <= 0;
        end
    end
endmodule
