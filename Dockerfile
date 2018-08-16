FROM ruby:2.5.1

ENV APP_HOME /app

RUN mkdir $APP_HOME
WORKDIR $APP_HOME

COPY Gemfile* $APP_HOME/
RUN bundle install

COPY . $APP_HOME

ENV PORT 3033
EXPOSE 3033

CMD ["ruby", "app.rb"]

