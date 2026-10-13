`timescale 1ns / 100ps
//Josh Schrock
//Date: October 16, 2024
//ECE433 Fall 2024
//Hexadecimal to 7 segment display
//Common-Cathode decoding
module HEXto7Segment (input [3:0] HEXnumber, output reg [7:0] SEGMENTS);
//SevenSegments are ordered from DP, G,F,E,D,C,B,A
//Segment A = SevenSegments[0].
//Active lower Enable
	always @ (HEXnumber)
			case (HEXnumber)
				4'd0:	SEGMENTS <= 8'B11000000;
				4'd1:	SEGMENTS <= 8'B11111001;
				4'd2:	SEGMENTS <= 8'B10100100;
				4'd3:	SEGMENTS <= 8'B10110000;
				4'd4:	SEGMENTS <= 8'B10011001;
				4'd5:	SEGMENTS <= 8'B10010010;
				4'd6:	SEGMENTS <= 8'B10000010;
				4'd7:	SEGMENTS <= 8'B11111000;
				4'd8:	SEGMENTS <= 8'B10000000;
				4'd9:	SEGMENTS <= 8'B10010000;
				4'd10:	SEGMENTS <= 8'B10001000;	
				4'd11:	SEGMENTS <= 8'B10000011;	
				4'd12:	SEGMENTS <= 8'B10100111;	
				4'd13:	SEGMENTS <= 8'B10100001;	
				4'd14:	SEGMENTS <= 8'B10000110;	
				4'd15:	SEGMENTS <= 8'B10001110;				
			default:	SEGMENTS <= 8'B10000000;
			endcase	
endmodule
