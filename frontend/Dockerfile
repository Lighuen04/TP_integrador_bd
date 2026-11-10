FROM nginx:stable-alpine
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY frontend/index.html frontend/styles.css frontend/app.js frontend/api.js /usr/share/nginx/html/
EXPOSE 80
