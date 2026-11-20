///////////////////////////////////////////////////////////////////////////////
//-------------------------------------------------------------------------
//                                                                
//  © 2022 Microchip Technology Inc. and its subsidiaries
//  All rights reserved.
//                                                                 
//  ANY USE OR REDISTRIBUTION IN PART OR IN WHOLE MUST BE HANDLED IN
//  ACCORDANCE WITH THE MICROCHIP LICENSE AGREEMENT AND MUST BE APPROVED
//  IN ADVANCE IN WRITING.
//
//-------------------------------------------------------------------------
// Title       : reset_synchronizer.v
// Created     : Sept-2018
// Description : Reset signal synchronizer
// Hierarchy   :
//               DDR_demo_top             
//                      --DDR_AXI     
//                           --reset_synchronizer   <-- This module
//                          
//-------------------------------------------------------------------------

module reset_synchronizer(
                          // Inputs
                          clock,
                          reset,
                          // Outputs
                          reset_sync);
  ////////////////////////////////////////////////////////////////////////////////
  // Parameters
  ////////////////////////////////////////////////////////////////////////////////
  parameter ACTIVE_HIGH_RESET = 0; // 0: reset input is active low
  // 1: reset input is active high
  ////////////////////////////////////////////////////////////////////////////////
  // Port directions
  ////////////////////////////////////////////////////////////////////////////////
  // Inputs
  input clock;
  input reset;
  // Outputs
  output reset_sync;
  ////////////////////////////////////////////////////////////////////////////////
  // Internal signals
  ////////////////////////////////////////////////////////////////////////////////
  reg[1 : 0] reset_sync_reg;
  generate
    if (ACTIVE_HIGH_RESET == 1)
      begin
        // Active high reset input
        always
          @(posedge clock or
            posedge reset)
          begin
            if (reset)
              begin
                reset_sync_reg[1 : 0] <= 2'b11;
              end
            else
              begin
                reset_sync_reg[1 : 0] <= { reset_sync_reg[0], 1'b0 };
              end
          end
      end
    else
      begin
        // Active low reset input
        always
          @(posedge clock or
            negedge reset)
          begin
            if (!reset)
              begin
                reset_sync_reg[1 : 0] <= 2'b00;
              end
            else
              begin
                reset_sync_reg[1 : 0] <= { reset_sync_reg[0], 1'b1 };
              end
          end
      end
  endgenerate
  assign reset_sync = reset_sync_reg[1];
endmodule // reset_synchronizer
