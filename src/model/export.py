import torch
import onnx
# 오픈소스 내부 model 폴더의 networks.py에서 Generator(딥러닝 모델)를 가져옵니다.
from model.networks import Generator 

# 1. pytorch 모델 객체 생성 및 가중치 파일 로드
model = Generator()
state_dict = torch.load("pretrained_weights.pth", map_location="cpu")

if 'G' in state_dict:
    model.load_state_dict(state_dict['G'])
else:
    model.load_state_dict(state_dict)

model.eval()

# 2. matlab 변환을 위한 더미 입력 데이터 생성 (이미지 5채널 + 마스크 1채널 = 총 6채널 입력 구조 맞추기)
dummy_x = torch.randn(1, 5, 256, 256)      # cnum_in=5 채널 규격에 맞춤
dummy_mask = torch.randn(1, 1, 256, 256)   # mask 채널 규격에 맞춤

print("🔄 1차 ONNX 기본 추출 중...")

# 3. 기본 ONNX 추출(용량이 커서 .data 파일이 쪼개져 나옴)
torch.onnx.export(model, (dummy_x, dummy_mask), "deepfill_v2.onnx", opset_version=11, verbose=False, do_constant_folding=True)

# 4. 쪼개진 두 파일 하나로 결합
try:
    print("🔄 매틀랩 온라인 호환성을 위해 분리된 가중치 파일 결합 시작...")
    model_onnx = onnx.load("deepfill_v2.onnx")
    
    # .data 가중치들을 .onnx 안으로 눌러 담아 단 하나의 파일로 저장
    onnx.save_model(
        model_onnx, 
        "deepfill_v2_combined.onnx", 
        save_as_external_data=False  # 외부로 쪼개지 않음 설정
    )
    print("단일 파일 변환 완료: deepfill_v2_combined.onnx")
except Exception as e:
    print(f"❌ 파일 결합 실패 에러 내용: {e}")
