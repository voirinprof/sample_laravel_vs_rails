FROM ruby:3.3

RUN apt-get update -qq && apt-get install -y \
    nodejs postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN gem install rails -v 7.1.3

WORKDIR /build

RUN rails new . --database=postgresql --skip-test --skip-jbuilder
COPY overlay/ ./
RUN bundle install

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /app
EXPOSE 3000
ENTRYPOINT ["docker-entrypoint.sh"]
CMD bash -c "until bin/rails db:prepare; do echo 'DB pas encore prête, retry dans 3s...'; sleep 3; done && bin/rails server -b 0.0.0.0"