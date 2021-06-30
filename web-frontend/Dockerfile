# build environment
FROM node:lts-alpine as build

# Set a workdir
WORKDIR /app

# Install packages in build environment, copy package files
# first to ensure that dependendencies are re-installed only
# when package files are modified.
ENV PATH /app/node_modules/.bin:$PATH
COPY package.json ./
COPY package-lock.json ./
RUN npm ci

# Build production app
COPY . ./
RUN npm run build

# production environment, This will only contain nginx and 
# static app files.
FROM nginx:stable-alpine
COPY --from=build /app/build /usr/share/nginx/html

# Serve the app via nginx
CMD ["nginx", "-g", "daemon off;"]
