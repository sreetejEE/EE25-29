# ============================================================
# Boolean board constraints for uart_fft_top
# ============================================================
#******Assigned by Vishwambhar************************
# ---------- Clock (100 MHz oscillator) ----------
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {clk}]
create_clock -period 10.000 -name gclk [get_ports clk]

# ---------- Configuration bank voltage ----------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

# ---------- Reset (Mapped to Push Button btn[0]) ----------
set_property -dict {PACKAGE_PIN J2  IOSTANDARD LVCMOS33} [get_ports {reset}]

# ---------- UART RX (USB serial from PC) ----------
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {uart_rxd}]
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {uart_txd}]

# ---------- LEDs led[7:0] ----------
set_property -dict {PACKAGE_PIN G1  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN G2  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN F1  IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN F2  IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN E1  IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN E2  IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN E3  IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN E5  IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN E6  IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN C3  IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN B2  IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN A2  IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN B3  IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN A3  IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN B4  IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN A4  IOSTANDARD LVCMOS33} [get_ports {led[15]}]

# ---------- 7-segment display 0 ----------
set_property -dict {PACKAGE_PIN D5  IOSTANDARD LVCMOS33} [get_ports {D0_AN[0]}]
set_property -dict {PACKAGE_PIN C4  IOSTANDARD LVCMOS33} [get_ports {D0_AN[1]}]
set_property -dict {PACKAGE_PIN C7  IOSTANDARD LVCMOS33} [get_ports {D0_AN[2]}]
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS33} [get_ports {D0_AN[3]}]
set_property -dict {PACKAGE_PIN D7  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[0]}]
set_property -dict {PACKAGE_PIN C5  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[1]}]
set_property -dict {PACKAGE_PIN A5  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[2]}]
set_property -dict {PACKAGE_PIN B7  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[3]}]
set_property -dict {PACKAGE_PIN A7  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[4]}]
set_property -dict {PACKAGE_PIN D6  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[5]}]
set_property -dict {PACKAGE_PIN B5  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[6]}]
set_property -dict {PACKAGE_PIN A6  IOSTANDARD LVCMOS33} [get_ports {D0_SEG[7]}]