`timescale 1ns/1ps
module tb_axi_lite_regs;
    reg clk=0; always #5 clk=~clk;
    reg rstn=0;
    reg [7:0] awaddr=0, araddr=0;
    reg awvalid=0, wvalid=0, arvalid=0, bready=0, rready=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=0;
    wire awready, wready, arready, bvalid, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    integer cycles=0;
    axi_lite_regs dut(
        .ACLK(clk),.ARESETn(rstn),
        .S_AXI_AWADDR(awaddr),.S_AXI_AWVALID(awvalid),.S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),.S_AXI_WSTRB(wstrb),.S_AXI_WVALID(wvalid),.S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),.S_AXI_BVALID(bvalid),.S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),.S_AXI_ARVALID(arvalid),.S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),.S_AXI_RRESP(rresp),.S_AXI_RVALID(rvalid),.S_AXI_RREADY(rready)
    );
    // Global watchdog catches stuck transactions.
    always @(posedge clk) begin
        cycles <= cycles+1;
        if (cycles>2000) $fatal(1,"TIMEOUT");
    end
    // Sample at clock edges before NBA updates; reset cancels stalled responses.
    reg stalled_b=0, stalled_r=0;
    reg [1:0] held_bresp, held_rresp;
    reg [31:0] held_rdata;
    always @(posedge clk) begin
        if (!rstn) begin
            stalled_b <= 0; stalled_r <= 0;
        end else begin
            if (stalled_b && (bvalid!==1'b1 || bresp!==held_bresp))
                $fatal(1,"B response changed while stalled");
            if (stalled_r && (rvalid!==1'b1 || rresp!==held_rresp || rdata!==held_rdata))
                $fatal(1,"R response changed while stalled");
            stalled_b <= bvalid && !bready;
            stalled_r <= rvalid && !rready;
            held_bresp <= bresp; held_rresp <= rresp; held_rdata <= rdata;
        end
    end
    task send_aw;
        input [7:0] addr;
        begin
            @(negedge clk); awaddr=addr; awvalid=1;
            @(posedge clk);
            while (awready!==1'b1) @(posedge clk);
            @(negedge clk); awvalid=0; awaddr=8'hfc;
        end
    endtask
    task send_w;
        input [31:0] value;
        begin
            @(negedge clk); wdata=value; wstrb=4'hf; wvalid=1;
            @(posedge clk);
            while (wready!==1'b1) @(posedge clk);
            @(negedge clk); wvalid=0; wdata=0; wstrb=0;
        end
    endtask
    task finish_b;
        input integer hold_cycles;
        integer n;
        begin
            wait(bvalid===1'b1);
            for (n=0; n<hold_cycles; n=n+1) begin
                @(negedge clk);
                if (bvalid!==1'b1 || bresp!==2'b00)
                    $fatal(1,"Invalid stalled B response");
                if (awready!==1'b0 || wready!==1'b0)
                    $fatal(1,"Write accepted while B outstanding");
            end
            @(negedge clk); bready=1;
            @(posedge clk);
            if (bvalid!==1'b1 || bresp!==2'b00) $fatal(1,"B handshake failed");
            @(negedge clk); bready=0;
            if (bvalid!==1'b0) $fatal(1,"BVALID not cleared");
        end
    endtask
    task split_write;
        input integer aw_first;
        input [31:0] value;
        integer n;
        begin
            if (aw_first) send_aw(8'h00); else send_w(value);
            for (n=0; n<6; n=n+1) begin
                @(negedge clk);
                if (bvalid!==1'b0) $fatal(1,"Premature write response");
                if (aw_first && awready!==1'b0) $fatal(1,"AW buffer lost");
                if (!aw_first && wready!==1'b0) $fatal(1,"W buffer lost");
            end
            if (aw_first) send_w(value); else send_aw(8'h00);
            finish_b(12);
            read_check(8'h00,value);
            $display("PASS split write aw_first=%0d, B stalled 12 cycles",aw_first);
        end
    endtask
    task stalled_read;
        integer n;
        begin
            @(negedge clk); araddr=0; arvalid=1; rready=0;
            @(posedge clk);
            if (arready!==1'b1) $fatal(1,"AR handshake failed");
            @(negedge clk); arvalid=0; araddr=8'h08;
            wait(rvalid===1'b1);
            // Change the source register while its previous read is stalled.
            // The response must retain the value captured at the AR handshake.
            fork
                write_reg(8'h00,32'h55667788,4'hf);
                begin
                    for (n=0; n<16; n=n+1) begin
                        @(negedge clk);
                        if (rvalid!==1'b1 || rdata!==32'h11223344 || rresp!==0)
                            $fatal(1,"Stalled read payload changed");
                        if (arready!==1'b0) $fatal(1,"AR accepted while R outstanding");
                    end
                end
            join
            @(negedge clk); rready=1;
            @(posedge clk);
            if (rvalid!==1'b1) $fatal(1,"R handshake failed");
            @(negedge clk); rready=0;
            if (rvalid!==1'b0) $fatal(1,"RVALID not cleared");
            read_check(0,32'h55667788);
            $display("PASS R stalled 16 cycles while source register changes");
        end
    endtask
    task reset_during_transaction;
        // 0: AW only; 1: W only; 2: both B and R responses stalled.
        input integer mode;
        integer n;
        begin
            if (mode==0) send_aw(0);
            else if (mode==1) send_w(32'hbad0bad0);
            else begin
                fork
                    send_aw(0);
                    send_w(32'hbad0bad0);
                    begin
                        @(negedge clk); araddr=8'h08; arvalid=1;
                        @(posedge clk);
                        if (arready!==1'b1) $fatal(1,"Reset setup AR failed");
                        @(negedge clk); arvalid=0;
                    end
                join
                wait(bvalid===1'b1 && rvalid===1'b1);
            end
            @(negedge clk); rstn=0;
            awvalid=0; wvalid=0; arvalid=0; bready=0; rready=0;
            // This DUT uses synchronous reset: check after active clock edges.
            repeat(3) begin
                @(posedge clk); #1;
                if (bvalid!==1'b0 || rvalid!==1'b0)
                    $fatal(1,"Responses not cleared by reset");
                if (dut.aw_pending!==1'b0 || dut.w_pending!==1'b0)
                    $fatal(1,"Partial write not cleared by reset");
            end
            @(negedge clk); rstn=1;
            for (n=0; n<5; n=n+1) begin
                @(negedge clk);
                if (bvalid!==1'b0 || rvalid!==1'b0)
                    $fatal(1,"Stale response after reset");
            end
            read_check(0,0); read_check(8'h08,0); read_check(8'h04,1);
            write_reg(8'h08,32'hcafef00d,4'hf);
            read_check(8'h08,32'hcafef00d);
            $display("PASS reset mode=%0d and post-reset recovery",mode);
        end
    endtask
    task write_reg;
        input [7:0] addr;
        input [31:0] value;
        input [3:0] strobe;
        begin
            @(negedge clk);
            awaddr=addr; awvalid=1;
            wdata=value; wstrb=strobe; wvalid=1;
            bready=0;
            // This test sends AW and W together; the RTL also buffers independent arrivals.
            @(posedge clk);
            if (!awready || !wready) $fatal(1,"Unexpected AW/W stall");
            @(negedge clk); awvalid=0; wvalid=0;
            wait(bvalid);
            if (bresp!==2'b00) $fatal(1,"BRESP failure");
            @(negedge clk); bready=1;
            @(negedge clk); bready=0;
            $display("WRITE addr=%h value=%h strobe=%h OK",addr,value,strobe);
        end
    endtask
    task read_check;
        input [7:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk); araddr=addr; arvalid=1; rready=0;
            @(posedge clk);
            if (!arready) $fatal(1,"Unexpected AR stall");
            @(negedge clk); arvalid=0;
            wait(rvalid);
            if (rresp!==2'b00 || rdata!==expected)
                $fatal(1,"READ addr=%h expected=%h got=%h",addr,expected,rdata);
            @(negedge clk); rready=1;
            @(negedge clk); rready=0;
            $display("READ addr=%h value=%h PASS",addr,expected);
        end
    endtask
    initial begin
        $dumpfile("wave.vcd"); $dumpvars(0,tb_axi_lite_regs);
        repeat(4) @(negedge clk); rstn=1;
        read_check(8'h00,32'h00000000);
        read_check(8'h04,32'h00000001);
        write_reg(8'h00,32'h12345678,4'hF);
        read_check(8'h00,32'h12345678);
        write_reg(8'h00,32'h0000AB00,4'b0010);
        read_check(8'h00,32'h1234AB78);
        write_reg(8'h08,32'hDEADBEEF,4'hF);
        read_check(8'h08,32'hDEADBEEF);
        write_reg(8'h04,32'hFFFFFFFF,4'hF);
        read_check(8'h04,32'h00000001);
        split_write(1,32'ha1b2c3d4);
        split_write(0,32'h11223344);
        stalled_read;
        // Independent addresses avoid imposing a same-address collision policy.
        fork
            write_reg(8'h08,32'h87654321,4'hf);
            read_check(8'h00,32'h55667788);
        join
        read_check(8'h08,32'h87654321);
        $display("PASS concurrent read and write");
        reset_during_transaction(0);
        reset_during_transaction(1);
        reset_during_transaction(2);
        $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
