FROM registry.suse.com/bci/nodejs

RUN git clone https://github.com/Front-End-Coders-Mauritius/frontendmu-astro.git

WORKDIR frontendmu-astro

RUN cp .env.example .env.deployment

RUN zypper --non-interactive install python3 make gcc-c++

RUN npm install -g npm

RUN npm install

ENTRYPOINT ["npm", "run", "dev", "--", "--host"]
