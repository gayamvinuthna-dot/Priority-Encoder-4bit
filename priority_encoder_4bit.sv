`timescale 1ns/1ps
module priority_encoder_4bit (
    input  logic [3:0] req,
    output logic [1:0] code,
    output logic       valid
);

    always_comb begin
        valid = 1'b1;
        code  = 2'b00;

        casex (req)
            4'b1xxx: code = 2'b11;
            4'b01xx: code = 2'b10;
            4'b001x: code = 2'b01;
            4'b0001: code = 2'b00;
            4'b0000: begin
                code  = 2'b00;
                valid = 1'b0;
            end
            default: begin
                code  = 2'b00;
                valid = 1'b0;
            end
        endcase
    end

endmodule
