# Zybo Z7-10 Constraints File for NPU Bitstream Generation

# 1. 시스템 클럭 (Zybo Z7은 K17 핀에서 125MHz 클럭을 제공)
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

# 2. 리셋 버튼 (Zybo Z7의 첫 번째 버튼 BTN0인 K18 핀에 연결)
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { reset }];

# 3. 할당되지 않은 핀(Unconstrained Pins) 에러 무시 강제 옵션 ★★★
# npu_top.v의 수많은 입출력 포트를 스위치나 LED에 전부 연결할 수 없으므로,
# Vivado가 "연결 안 된 핀이 너무 많다"며 bit 생성을 멈추는 것을 방지
set_property BITSTREAM.General.UnconstrainedPins {Allow} [current_design]