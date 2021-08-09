FROM ruby:3-alpine

ARG APP_NAME=rails_app

RUN apk add --update build-base postgresql-dev tzdata

ENV PATH="/root/.local/share/gem/ruby/3.0.0/bin:$PATH"
RUN gem install rails --no-document

CMD [ "rails", "new", "$APP_NAME", "--database=postgresql", "--skip-bundle" ]
