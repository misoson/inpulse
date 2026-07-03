%% [1] MATLAB으로 모델 import & 레이어 식별
% 1. 모델 임포트 (인페인팅 모델은 연속된 값 출력하므로 regression 설정)
net = importONNXNetwork('deepfill_v2.onnx', 'OutputLayerType', 'regression');

% 2. 네트워크 구조 분석 및 시각화 창 띄우기
analyzeNetwork(net); 


%% [2] feature 추출 & INT4/INT8 양자화
% 1. 테스트 이미지 로드 및 전처리 (256x256 크기 조정)
img = imread('test_image.jpg'); %테스트 이미지 로드
img_resized = imresize(img, [256 256]);

% 파이썬 모델 규격에 맞춰 이미지 채널(RGB 3채널)과 가짜 마스크 데이터를 합쳐서 던져줍니다.
% (원래 모델 입력이 5채널 이미지 데이터와 1채널 마스크 데이터를 forward에서 동시에 받기 때문)
if size(img_resized, 3) == 3
    % 이미지를 0~1 사이 float32로 변환 후, 채널 수 5개에 맞추기 위해 dummy 데이터Cat
    img_double = single(img_resized) / 255.0;
    dummy_x = cat(3, img_double, zeros(256, 256, 2, 'single')); 
    dummy_mask = zeros(256, 256, 1, 'single');
else
    error('test_image.jpg 파일은 RGB 컬러 이미지여야 합니다.');
end

% 2. 특정 레이어의 연산 결과(Activations) 추출
% ※ 'conv_1_output' 부분은 analyzeNetwork 창을 보고 실제 존재하는 첫 번째 레이어 이름으로 수정해야 할 수 있습니다.
golden_features = activations(net, dummy_x, dummy_mask, 'conv_1_output');

% 3. Fixed-Point (고정소수점) 양자화 적용 (INT8 규격)
quantized_golden = fi(golden_features, 1, 8, 4);


%% [3] Verilog용 16진수 텍스트 파일 추출
% 1. 행렬을 1차원 배열로 펼치기
flat_data = quantized_golden(:);

% 2. 텍스트 파일 열기 (골든 정답 데이터)
fileID = fopen('golden_out_layer1.txt', 'w');

% 3. 양자화된 데이터를 16진수 문자열로 변환하여 저장
hex_str = hex(flat_data);

for i = 1:length(hex_str)
    fprintf(fileID, '%s\n', hex_str(i, :));
end

fclose(fileID);

disp('golden_out_layer1.txt 파일 생성 완료');
