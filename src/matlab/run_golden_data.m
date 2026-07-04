%% [1] MATLAB으로 모델 import & 레이어 식별
% 최신 매틀랩 규격에 맞게 함수명을 수정하고, 우리가 합친 단일 파일을 불러옵니다.
net = importNetworkFromONNX('deepfill_v2_combined.onnx', 'OutputLayerType', 'regression');

% 네트워크 구조 시각화 창 띄우기
analyzeNetwork(net); 


%% [2] 입력 이미지 전처리 및 1번 파일(input_img.txt) 추출
img = imread('test_image.jpg');
img_resized = imresize(img, [256 256]);

if size(img_resized, 3) == 3
    img_double = single(img_resized) / 255.0;
    dummy_x = cat(3, img_double, zeros(256, 256, 2, 'single')); 
    dummy_mask = zeros(256, 256, 1, 'single');
else
    error('test_image.jpg 파일은 RGB 컬러 이미지여야 합니다.');
end

% 1. 입력 픽셀 데이터(input_img.txt) 추출 및 양자화
quantized_input = fi(dummy_x, 1, 8, 4);
flat_input = quantized_input(:);
f_input = fopen('input_img.txt', 'w');
hex_input = hex(flat_input);
for i = 1:length(hex_input)
    fprintf(f_input, '%s\n', hex_input(i, :));
end
fclose(f_input);
disp('1. input_img.txt 파일 생성 완료');


%% [3] 2번 파일(weights_layer1.txt) 추출 (가중치 데이터)
% 모델의 첫 번째 Convolution 레이어 가중치를 가져옵니다. 
% ※ 만약 에러가 나면 analyzeNetwork 창에서 첫 번째 conv 레이어의 정확한 이름을 확인해야 합니다.
try
    layer1_weights = net.Layers(2).Weights;
    quantized_weights = fi(layer1_weights, 1, 8, 4);
    flat_weights = quantized_weights(:);
    f_weights = fopen('weights_layer1.txt', 'w');
    hex_weights = hex(flat_weights);
    for i = 1:length(hex_weights)
        fprintf(f_weights, '%s\n', hex_weights(i, :));
    end
    fclose(f_weights);
    disp('2. weights_layer1.txt 파일 생성 완료');
catch
    disp('레이어 가중치 추출 실패: analyzeNetwork 창을 보고 레이어 인덱스나 이름을 확인해 주세요.');
end


%% [4] 3번 파일(golden_out_layer1.txt) 추출 (골든 정답 데이터)
% 특정 레이어의 출력 결과(Feature Map)를 추출합니다.
% ※ 'conv_1_output'은 analyzeNetwork 창에 나오는 첫 번째 conv 레이어의 출력 이름이어야 합니다.
try
    golden_features = activations(net, dummy_x, dummy_mask, 'conv_1_output');
    quantized_golden = fi(golden_features, 1, 8, 4);
    flat_golden = quantized_golden(:);
    f_golden = fopen('golden_out_layer1.txt', 'w');
    hex_golden = hex(flat_golden);
    for i = 1:length(hex_golden)
        fprintf(f_golden, '%s\n', hex_golden(i, :));
    end
    fclose(f_golden);
    disp('3. golden_out_layer1.txt 파일 생성 완료!');
catch
    disp('골든 데이터 추출 실패: conv_1_output 레이어 이름을 확인해 주세요.');
end

disp('모든 텍스트 파일 추출 작업 완료');
