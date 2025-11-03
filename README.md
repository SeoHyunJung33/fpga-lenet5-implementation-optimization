# FPGA Implementation and Optimization of LeNet-5

본 프로젝트는 CNN 기반 이미지 분류 모델인 **LeNet-5**를 FPGA 상에 구현하고,  
스트리밍 데이터플로우와 파이프라인 최적화를 통해 **처리량·지연·자원 효율**을 동시에 확보하는 것을 목표로 한다.

---

## 1. 수행 과제 개요 및 목표

- FPGA 상에서 VGA 해상도(640×480) 입력을 받아, 전처리 → LeNet-5 추론 → 결과 전송까지를 **End-to-End 하드웨어 파이프라인**으로 구성
- 프레임 전체를 저장하지 않고, **센서 스트림 기반 실시간 처리**를 통해 지연(latency)을 최소화
- 제한된 BRAM/Logic 자원 내에서 **adder tree 파이프라이닝**, **line buffer 기반 윈도우 생성**, **int8 quantization**을 적용해 자원 대비 효율을 극대화
- AWS F1 환경의 **SDE(Streaming Data Engine)** 및 PCIe 인터페이스와 연동하여 Host CPU와 통신

---

## 2. CNN 하드웨어 구현 시 주요 제약

하드웨어에서 CNN 모델을 직접 구현할 때 고려해야 할 대표적인 제약은 다음과 같다.

1. **한정된 메모리 대역폭과 연산 효율**
   - CPU/GPU와 달리 온칩 메모리 용량·대역폭이 제한적이며, 외부 메모리 접근 비용이 크다.
   - 따라서 **frame buffer를 최소화**하고, line buffer·window generator·streaming 구조를 사용해 데이터 재사용을 극대화한다.

2. **Timing / Clock / Interface 이슈**
   - 센서, 연산 코어, SDE/PCIe, Host 등이 서로 다른 클록 도메인을 사용한다.
   - Toggle 기반 **CDC(Clock Domain Crossing)**, FF 동기화, 프레임/라인 경계 제어를 통해 metastability를 방지하고 안정적인 인터페이스를 보장한다.

---

## 3. 시스템 아키텍처

<img width="543" height="214" alt="image" src="https://github.com/user-attachments/assets/0a10af60-37f7-4c8d-9e6c-6cce0010af16" />

시스템은 크게 세 블록과 Host로 구성된다.

- **Pseudo Sensor**
  - 0~9 숫자 이미지를 VGA 포맷(640×480, 30FPS)으로 출력하는 가상 센서 모듈

- **LeNet-5 Accelerator (전처리 + CNN 코어)**
  - 640×480 스트림을 32×32 CNN 입력으로 변환
  - LeNet-5 Conv / Pool / FC 연산 수행 후 10-class score 생성

- **SDE (Streaming Data Engine)**
  - AWS F1 Shell IP와 연동되는 스트리밍 엔진
  - LeNet-5 결과를 패킷화하여 **PCIe**를 통해 Host CPU로 전송

데이터 흐름:

`Pseudo Sensor → 전처리(Front-End) → LeNet-5 Core → SDE → Host`

---

## 4. 전처리 파이프라인 (Front-End)

### 4.1 VGA Frame 모듈

- 입력: **640×480 @ 30FPS**
- 타이밍 파라미터
  - Horizontal: Active 640 / Front Porch 16 / Sync 96 / Back Porch 48 → Total 800
  - Vertical: Active 480 / Front Porch 10 / Sync 2 / Back Porch 33 → Total 525
  - Pixel Clock ≈ 12.6 MHz (800 × 525 × 30)
- 기능
  - VGA TCON 생성 (HSYNC/VSYNC, DE 등)
  - Dual-port BRAM을 이용해 스트림 수신 및 다른 도메인(FPGA core)으로 동시에 공급
  - Clocking & **Toggle-based CDC** 로 픽셀 클록과 연산 클록 간 데이터 정합

### 4.2 MaxPooling

- 640×480 입력을 **20×20 타일 단위**로 나누어 각 타일에서 max 값을 추출
- 결과로 **32×24 feature map**을 생성
- 프레임/라인 경계와 맞추어 pooling을 수행해 CNN 입력 영역이 균일하게 유지되도록 설계

### 4.3 Zero Padding

- 32×24 feature map을 상·하 라인에 zero를 삽입하여 **32×32**로 확장
- padding counter를 통해 패딩 영역만 선택적으로 0을 기록하고, 나머지 영역은 원본 데이터를 유지

### 4.4 Quantization

- 데이터가 존재하는 영역을 **signed 8-bit**로 quantization
- Zero-point 처리를 적용하여, 이후 LeNet-5 연산기가 별도의 정규화 없이 바로 사용할 수 있도록 맞춤

---

## 5. LeNet-5 연산기 (LeNet-5 Core)

<img width="706" height="244" alt="image" src="https://github.com/user-attachments/assets/ee079d2d-9cbf-42eb-ab5e-d03a8f06d349" />

LeNet-5 구조를 하드웨어 친화적으로 재구성하여 streaming 기반으로 동작하도록 설계하였다.

### 5.1 Conv1

- 입력: 32×32×1  
- 출력: 28×28×6
- `win5x5_stream`
  - 프레임 전체를 저장하지 않고 **line buffer**를 이용해 실시간으로 5×5 window 생성
  - 이를 통해 frame buffer용 BRAM 사용량을 크게 절감
- `adder_tree_pipe`
  - 25개의 곱셈 결과를 tree 구조로 합산
  - 중간에 레지스터를 삽입하여 **adder tree 파이프라이닝**을 수행, critical path를 단축

### 5.2 Sub2 (Pooling 1)

- 입력: 28×28×6  
- 출력: 14×14×6
- 입력에 ReLU를 적용해 음수 값을 제거
- 2×2 maxpooling으로 다운샘플링하여 feature map 크기를 절반으로 축소

### 5.3 Conv3

- 입력: 14×14×6  
- 출력: 10×10×16
- 6ch → 16ch, 총 96개의 5×5 필터
- `win5x5_stream` + **ping-pong window buffer**
  - Window A / Window B 두 버퍼를 번갈아 사용
  - 한쪽에서 연산 중일 때 다른 쪽이 다음 window를 준비하여 파이프라인이 끊기지 않도록 구성
- 각 output channel에 대해 adder tree를 이용한 convolution 수행

### 5.4 Sub4 (Pooling 2)

- 입력: 10×10×16  
- 출력: 5×5×16
- ReLU + 2×2 maxpooling
- 이후 FC 계층으로 전달될 compact feature map을 생성

### 5.5 Conv5 / FC120

- 입력: 5×5×16  
- 출력: 1×1×120
- 5×5×16 전체를 flatten하여 120개의 뉴런에 연결하는 형태로 구현
- 내부 동작
  - `IN_CH` 카운터를 통해 input channel 누적(acc) 시점을 제어
  - tree adder를 이용해 lane_sum_flat[…] 등의 partial sum을 누적
  - FSM: **COLLECT → ACC → FINALIZE → EMIT**
    - COLLECT: 5×5 tap(25개)을 버퍼에 수집
    - ACC: 각 output channel에 대해 adder tree 결과를 누적
    - FINALIZE: bias 및 ReLU/Trunc 연산 수행
    - EMIT: out_mask 및 valid_out을 기반으로 결과 출력

### 5.6 FC84 및 출력 계층

- **FC120 → FC84 → FC10** 구조
  - FC120: 입력 120, 출력 84
  - FC84: 입력 84, 출력 10 (최종 score)
- weight/bias는 BRAM 기반 ROM으로 저장되며, adder tree 구조를 재사용해 MAC 연산을 수행
- slack을 줄이기 위해 weight/bias ROM과 연산 파이프라인 사이에 버퍼를 배치

---

## 6. 후처리 및 SDE 통합

<img width="656" height="264" alt="image" src="https://github.com/user-attachments/assets/89287509-2766-4054-bc65-001aa77def5f" />

### 6.1 `cl_sde/design/cl_sde.sv`

- 시스템 상위 허브 역할
  - 입력(ROM/pseudo) → 전처리 → LeNet-5 core → SDE(AXIS) 경로를 한 곳에서 연결
- AWS Shell과의 연동
  - Shell의 clk/rst/irq, 스트림 포트 등을 사용자 로직에 매핑
- 시스템 관리
  - 모듈 교체·추가 시 인스턴스/배선을 수정하는 것만으로 전체 동작을 제어할 수 있도록 구조화

### 6.2 `cl_sde/design/lenet5_accel_wrap.v`

- 전처리 출력(valid/pixel)을 받아 LeNet-5 core와 연결
- LeNet-5 결과를 128b×2 beat 패킷으로 정렬해 SDE로 전송
- BMG ROM 인스턴스 및 주소 정렬, 파이프라인 정합(1클록 지연 보정)을 담당
- T0/T1(1장 입력) 기준으로 결과 완료 시 IRQ를 발생시켜 Host에서 상태를 확인할 수 있도록 지원

### 6.3 `cl_sde/design/lenet5_core.v`

- **연산 엔진**: LeNet-5의 Conv/Pool/FC 계산을 수행하고 최종 **10개 score**를 생성
- **메모리 인터페이스**:
  - 각 계층의 weight/bias ROM의 `addr`/`dout`를 구동하고 내부 데이터 흐름에 공급
- **타이밍 정합**:
  - 입력 스트리밍(valid)–주소 생성기–연산 파이프라인을 맞춰, `done` 및 score 출력 타이밍을 보장

---

## 7. 주요 결과

### 7.1 End-to-End 스트리밍 아키텍처

- 프레임 전체 저장 없이 **센서 → 전처리 → 연산기**로 이어지는 순수 스트리밍 파이프라인을 구현
- 지연(latency)을 낮추는 동시에, 프레임당 처리 시간이 일정하게 유지되는 구조를 확보

### 7.2 하드웨어 전처리 파이프라인

- 640×480 입력을
  1. 다운샘플(MaxPooling),
  2. Zero Padding,
  3. 정규화 및 int8 quantization
  까지 **모두 FPGA 상에서 처리**
- Host CPU는 결과만 받아보기 때문에, **호스트 부하를 줄이고 실시간성**을 확보할 수 있음

### 7.3 LeNet-5 연산기 구조

- Line buffer 기반 5×5 window, 파이프라인된 adder tree, ReLU + 2×2 maxpool을 streaming으로 연결
- Conv/Pool/FC 전체를 **pipeline-friendly 구조**로 설계하여, 자원 대비 높은 성능을 얻음

---

## 8. 결과 활용 및 시사점

- **엣지 실시간 적용성**
  - 일반적인 지연 특성을 가지므로 임베디드 카메라, 공정 검사 등 **실시간 비전 응용**에 바로 적용 가능하다.

- **자원·전력 효율 확장성**
  - int8 quantization + streaming 패턴을 그대로 확장하면, 더 큰 CNN 모델에서도  
    처리량 향상 또는 자원·전력 절감 전략을 선택적으로 적용할 수 있다.

- **안정적 이식성**
  - 클록 도메인 분리, 프레임/라인 경계 제어, 센서·Host 인터페이스 추상화를 통해  
    해상도·센서·Host 프로토콜이 바뀌어도 비교적 쉽게 포팅·통합이 가능하다.

---

## 1. 현황
- 전처리와 LeNet-5 연산기는 Vivado Simulation 단독 환경에서 정상 동작 확인했습니다.
- 이를 cl_sde 내부에 통합하고 CSR 리포트까지 만들려 했지만, 합성 단계에서 반복된 오류로 하드웨어 빌드 및 리포트 검증을 수행하지 못했습니다.

## 2. 제출한 프로젝트 압축 파일의 경로
- cl_ip: ~/aws-fpga/hdk/common/ip/cl_ip
- design : ~/aws-fpga/hdk/cl/examples/cl_sde/design

## 3. 문제 사항
 - 인스턴스 내부 vivado 버전: Vivado 2024.1 
 - 문제 파일(주요 증상 위치)
  1) cl_sde.sv
  2) system_top_0.xcix (패키징된 IP)
-> 이 IP가 다른 디바이스에서 패키징 되어 그 과정에서 오류가 생겼습니다. 또한 2017 version으로 패키징되어서 Upgrade시켜야하지만 read only로 locked이 풀리지 않는 문제가 발생했습니다. 시간 부족의 이유로 custom ip를 재생성하지 못했습니다.

## 4. 시뮬레이션 확인
- 전처리 + LeNet5 연산기 RTL만 분리하여 Vivado Behavioral Simulation 수행했습니다.
- CL 통합 전 단계에서는 기능상 문제 없는걸로 확인되었습니다.

- Lenet5 accelerator simulation

<img width="262" height="179" alt="image" src="https://github.com/user-attachments/assets/17b64318-3959-4ba3-a92a-09c32397f78e" />
<img width="283" height="192" alt="image" src="https://github.com/user-attachments/assets/06fc1f19-3f14-4dcd-a246-affd279d4175" />

- 본 이미지는 lenet5 accelerator의 시뮬레이션 출력 결과입니다. conv1->sub2->conv3->sub4->conv5->fc1->fc2까지 데이터 전달이 잘 나오는 것을 확인하였고, PRED_DIGIT은 예측 숫자를 의미하며 입력 이미지 7을 넣었을 때 7이 정상적으로 나오는 것을 확인하였습니다.

<img width="569" height="268" alt="image" src="https://github.com/user-attachments/assets/682477a3-0fa0-4e5d-a20c-3b75f6b025b8" />
<img width="597" height="108" alt="image" src="https://github.com/user-attachments/assets/759c434f-d414-473c-aef8-66821edba569" />

- 전처리 simulation

<한 프레임 데이터>

<img width="678" height="407" alt="image" src="https://github.com/user-attachments/assets/75327f7a-e532-4344-8d2a-a74612d24b5a" />

<한 프레임 딜레이 후 데이터 out>

<img width="666" height="397" alt="image" src="https://github.com/user-attachments/assets/7174250b-e334-48ed-b469-00516b2c8532" />

- 최종 출력은 q_* 신호들로 확인했고, 특히 q_valid, q_pixel, q_is_pad, q_line_last, q_frame_last를 중심으로 동작을 체크했습니다.
- 첫 번째 파형:
한 프레임이 연속으로 출력된 경우입니다. q_valid가 켜져 있는 동안 정확히 1024클럭(= 32×32)만큼 데이터가 나오고, q_line_last가 라인 끝에서 32번 펄스가 발생해서 한 라인이 32픽셀로 잘 끊기는 걸 확인했습니다. 프레임의 마지막 픽셀에서는 q_frame_last가 1클럭 올라오면서 프레임이 끝났다고 알려줍니다. 패딩 동작도 명확했는데, q_is_pad가 1인 구간에서는 q_pixel이 0으로 유지됐고, 프레임 앞쪽과 끝쪽 패딩(마지막 4라인)이 잘 보였습니다. 중간 구간은 실제 유효 영상이 양자화된 값들로 채워졌습니다. 콘솔 로그에도 out=1024 (exp 1024), lines=32 (exp 32)로 기대치와 동일하게 나왔습니다.
- 두 번째 파형:
 프레임 사이에 공백이 길게 보이는 경우입니다. 테스트벤치에서 VGA 클록과 타이밍을 같이 보여주도록 해놔서, 입력과 출력 사이에 파이프라인 지연과 인터페이스 대기가 그대로 드러나 공백이 길게 보였습니다. 기능상 문제는 없고, 다음 프레임도 첫 번째와 똑같이 1024픽셀, 32라인 구조로 정상 출력됐습니다. 즉, 한 프레임 딜레이가 있는 버전이라고 보면 됩니다. 이때도 q_line_last랑 q_frame_last 타이밍은 그대로 정확했습니다.

- simulation 정리: 전처리, 양자화 경로는 시뮬레이션에서 규격대로 잘 동작했습니다. q_valid 기준으로 프레임당 1024픽셀, 32라인이 맞았고, q_is_pad가 1인 곳은 전부 제로패딩(픽셀=0)이라 구간 구분이 확실했습니다. 라인/프레임 끝 표시(q_line_last, q_frame_last)도 원하는 타이밍에 딱 맞았습니다. 두 번째 캡처에서 프레임 사이 공백이 길게 보이는 건 테스트벤치 구성(VGA 타이밍 표시) 때문이라 동작 문제는 아니었습니다.

## 5. 하드웨어 합성/구현 단계에서의 실패 현황

- 합성 시 반복적으로 아래 에러 발생:
ERROR: [Synth 8-5809] Error generated from encrypted envelope. [/home/ubuntu/aws-fpga/hdk/cl/examples/cl_sde/build/src_post_encryption/cl_sde.sv:252] 
ERROR: [Synth 8-5809] Error generated from encrypted envelope. [/home/ubuntu/aws-fpga/hdk/cl/examples/cl_sde/build/src_post_encryption/cl_sde.sv:23]

## 6. report 추출 명령어
$ cd ~/aws-fpga
$ source hdk_setup.sh
$ cd hdk/cl/examples/cl_sde
$ export CL_DIR=$(pwd)
$ cd build/scripts
./aws_build_dcp_from_cl.py -c cl_sde




