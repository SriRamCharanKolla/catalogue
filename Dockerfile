FROM node:20.1.0-alpine AS builder
WORKDIR /app
COPY package.json .
COPY *.js .
RUN npm install


FROM node:20.1.0-alpine
WORKDIR /app
EXPOSE 8080
COPY --from=builder /app /app 
ENV MONGO="true" \
    MONGO_URL="mongodb://mongodb:27017/catalogue"
RUN addgroup -S roboshop && adduser -S roboshop -G roboshop && \
    apk --no-cache update && apk --no-cache upgrade
RUN chown -R roboshop:roboshop /app
USER roboshop
CMD ["server.js"]
ENTRYPOINT ["node"]

# FROM node:20
# # this creates /app and move there
# WORKDIR /app
# COPY package.json .
# COPY *.js .
# RUN npm install
# ENV MONGO="true" \
#     MONGO_URL="mongodb://mongodb:27017/catalogue"
# CMD ["node", "server.js"]