`timescale 1ns/1ps

interface pe_if(input logic clk);
    logic [3:0] req;
    logic [1:0] code;
    logic valid;
endinterface

class pe_transaction;
    rand bit [3:0] req;
         bit [1:0] code;
         bit valid;

    constraint req_c {
        req inside {[0:15]};
    }

    function void display(string tag);
        $display("[%0s] req=%b code=%b valid=%b", tag, req, code, valid);
    endfunction
endclass

class pe_generator;
    mailbox gen2drv;
    int count;

    function new(mailbox gen2drv, int count);
        this.gen2drv = gen2drv;
        this.count = count;
    endfunction

    task run();
        pe_transaction tr;
        repeat (count) begin
            tr = new();
            if (!tr.randomize())
                $display("[GENERATOR] Randomization Failed");
            else begin
                tr.display("GENERATOR");
                gen2drv.put(tr);
            end
        end
    endtask
endclass

class pe_driver;
    virtual pe_if vif;
    mailbox gen2drv;
    int count;

    function new(virtual pe_if vif, mailbox gen2drv, int count);
        this.vif = vif;
        this.gen2drv = gen2drv;
        this.count = count;
    endfunction

    task run();
        pe_transaction tr;
        repeat (count) begin
            gen2drv.get(tr);
            @(posedge vif.clk);
            vif.req <= tr.req;
            tr.display("DRIVER");
        end
    endtask
endclass

class pe_monitor;
    virtual pe_if vif;
    mailbox mon2scb;
    mailbox mon2cov;
    int count;

    function new(virtual pe_if vif, mailbox mon2scb, mailbox mon2cov, int count);
        this.vif = vif;
        this.mon2scb = mon2scb;
        this.mon2cov = mon2cov;
        this.count = count;
    endfunction

    task run();
        pe_transaction tr;
        repeat (count) begin
            @(posedge vif.clk);
            #1;
            tr = new();
            tr.req = vif.req;
            tr.code = vif.code;
            tr.valid = vif.valid;
            tr.display("MONITOR");
            mon2scb.put(tr);
            mon2cov.put(tr);
        end
    endtask
endclass

class pe_scoreboard;
    mailbox mon2scb;
    int count;
    int pass_count;
    int fail_count;

    function new(mailbox mon2scb, int count);
        this.mon2scb = mon2scb;
        this.count = count;
        pass_count = 0;
        fail_count = 0;
    endfunction

    function void expected(
        input bit [3:0] req,
        output bit [1:0] exp_code,
        output bit exp_valid
    );
        exp_code = 2'b00;
        exp_valid = 1'b1;

        casex (req)
            4'b1xxx: exp_code = 2'b11;
            4'b01xx: exp_code = 2'b10;
            4'b001x: exp_code = 2'b01;
            4'b0001: exp_code = 2'b00;
            4'b0000: begin
                exp_code = 2'b00;
                exp_valid = 1'b0;
            end
            default: begin
                exp_code = 2'b00;
                exp_valid = 1'b0;
            end
        endcase
    endfunction

    task run();
        pe_transaction tr;
        bit [1:0] exp_code;
        bit exp_valid;

        repeat (count) begin
            mon2scb.get(tr);
            expected(tr.req, exp_code, exp_valid);

            if ((tr.code == exp_code) && (tr.valid == exp_valid)) begin
                pass_count++;
                $display("[SCOREBOARD] PASS req=%b exp_code=%b act_code=%b exp_valid=%b act_valid=%b",
                         tr.req, exp_code, tr.code, exp_valid, tr.valid);
            end
            else begin
                fail_count++;
                $display("[SCOREBOARD] FAIL req=%b exp_code=%b act_code=%b exp_valid=%b act_valid=%b",
                         tr.req, exp_code, tr.code, exp_valid, tr.valid);
            end
        end

        $display("======================================");
        $display("FINAL SCOREBOARD REPORT");
        $display("PASS COUNT = %0d", pass_count);
        $display("FAIL COUNT = %0d", fail_count);
        $display("======================================");
    endtask
endclass

class pe_coverage;
    mailbox mon2cov;
    int count;

    bit [3:0] req_cp;
    bit [1:0] code_cp;
    bit valid_cp;

    covergroup pe_cg;
	option.per_instance = 1;
        cp_req: coverpoint req_cp {
            bins req_values[] = {[0:15]};
        }

        cp_code: coverpoint code_cp {
            bins code_0 = {2'b00};
            bins code_1 = {2'b01};
            bins code_2 = {2'b10};
            bins code_3 = {2'b11};
        }

        cp_valid: coverpoint valid_cp {
            bins invalid = {1'b0};
            bins valid = {1'b1};
        }

        req_code_cross: cross cp_req, cp_code;
    endgroup

    function new(mailbox mon2cov, int count);
        this.mon2cov = mon2cov;
        this.count = count;
        pe_cg = new();
    endfunction

    task run();
        pe_transaction tr;
        repeat (count) begin
            mon2cov.get(tr);
            req_cp = tr.req;
            code_cp = tr.code;
            valid_cp = tr.valid;
            pe_cg.sample();
        end

        $display("======================================");
        $display("FUNCTIONAL COVERAGE REPORT");
        $display("Coverage = %0.2f %%", pe_cg.get_coverage());
        $display("======================================");
    endtask
endclass

class pe_environment;
    pe_generator gen;
    pe_driver drv;
    pe_monitor mon;
    pe_scoreboard scb;
    pe_coverage cov;

    mailbox gen2drv;
    mailbox mon2scb;
    mailbox mon2cov;

    virtual pe_if vif;
    int count;

    function new(virtual pe_if vif, int count);
        this.vif = vif;
        this.count = count;

        gen2drv = new();
        mon2scb = new();
        mon2cov = new();

        gen = new(gen2drv, count);
        drv = new(vif, gen2drv, count);
        mon = new(vif, mon2scb, mon2cov, count);
        scb = new(mon2scb, count);
        cov = new(mon2cov, count);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
            cov.run();
        join
    endtask
endclass

module tb_top;

    logic clk;
    int count;

    pe_if pif(clk);

    priority_encoder_4bit dut (
        .req (pif.req),
        .code (pif.code),
        .valid (pif.valid)
    );

    pe_environment env;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    

    initial begin
        count = 32;
        pif.req = 4'b0000;

        env = new(pif, count);

        $display("======================================");
        $display("4-bit Priority Encoder Verification Started");
        $display("======================================");

        env.run();

        $display("======================================");
        $display("4-bit Priority Encoder Verification Completed");
        $display("======================================");

        #20;
        $finish;
    end

endmodule
