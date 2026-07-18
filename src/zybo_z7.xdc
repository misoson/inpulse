# =============================================================================
# Zybo Z7-10 Constraints File for NPU SoC (Zynq AXI Integration)
#
# [안내] NPU를 Zynq PS(CPU)와 AXI 버스로 내부에서 결합했기 때문에, 
# 기존 PL 영역의 외부 clk와 reset 포트는 더 이상 최상위 외부에 노출되지 않습니다.
# Vivado의 'Port Not Found' 에러를 방지하기 위해 기존 핀 매핑을 주석 처리합니다.
# (Zynq 시스템의 Clock과 Reset은 블록 디자인 내부에서 자동으로 매핑됩니다.)
# =============================================================================

# 1. 시스템 클록 (Zynq PS 내부에서 FCLK_CLK0를 공급하므로 주석 처리)
# set_property -dict { PACKAGE_PIN K17    IOSTANDARD LVCMOS33 } [get_ports { clk }];
# create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }];

# 2. 리셋 버튼 (Zynq 내부 Reset 블록이 담당하므로 주석 처리)
# set_property -dict { PACKAGE_PIN K18    IOSTANDARD LVCMOS33 } [get_ports { reset }];

# 3. 비트스트림 옵션 (이제 외부 핀 개수 초과 문제가 완벽히 해결되었으므로 비활성화)
# set_property BITSTREAM.General.UnconstrainedPins {Allow} [current_design]