FROM python:3.12-slim
WORKDIR /tools
COPY database/seed /tools/seed
RUN pip install --no-cache-dir -r /tools/seed/requirements.txt
ENTRYPOINT ["python", "/tools/seed/generar_datos.py"]
