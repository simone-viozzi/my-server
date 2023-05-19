FROM python:3.10 as builder

ENV PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  PIP_NO_CACHE_DIR=true

RUN pip3 install --user torch --index-url https://download.pytorch.org/whl/cu118
RUN pip3 install --user transformers tqdm numpy scikit-learn scipy nltk sentencepiece fastapi Pillow uvicorn[standard]
RUN pip3 install --user sentence-transformers
# Facial Recognition Stuff
RUN pip3 install --user insightface onnxruntime-gpu

FROM nvidia/cuda:11.6.0-cudnn8-runtime-ubuntu18.04

# Add the deadsnakes PPA for Python 3.10
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update

RUN DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC \
    apt-get install -y python3.10 \
                        python3.10-dev \
                        python3-pip \
                        python3.10-distutils && \
    rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

RUN mkdir -p /root/.local/lib/python3.10/site-packages

COPY --from=builder /root/.local/lib/python3.10/site-packages /root/.local/lib/python3.10/site-packages

RUN ln -s /usr/bin/python3.10 /usr/bin/python

ENV TRANSFORMERS_CACHE=/cache \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1

WORKDIR /usr/src/app

COPY . .
ENV PYTHONPATH=`pwd`
CMD ["python", "src/main.py"]
