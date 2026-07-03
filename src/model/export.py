import torch
# 오픈소스 내부 model 폴더의 networks.py에서 Generator(딥러닝 모델)를 가져옵니다.
from model.networks import Generator 

# 1. 모델 선언 및 가중치 파일 로드
model = Generator()
model.load_state_dict(torch.load('pretrained_weights.pth', map_location='cpu')['G'])
model.eval()

# 2. 매틀랩 변환을 위한 가짜 입력 데이터(뼈대) 생성
dummy_x = torch.randn(1, 5, 256, 256)      # cnum_in=5 채널 규격에 맞춤
dummy_mask = torch.randn(1, 1, 256, 256)   # mask 채널 규격에 맞춤

# 3. ONNX 포맷으로 모델 추출
torch.onnx.export(model, (dummy_x, dummy_mask), "deepfill_v2.onnx", opset_version=11, verbose=True)
print("deepfill_v2.onnx 파일 추출 완료")
