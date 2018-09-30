module Sequel
  module Auditer
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        Sequel::Auditer::Railtie.env = env
        @app.call(env)
      end
    end
	
    class Railtie < ::Rails::Engine
      initializer "sequel-auditer_railtie.configure_rails_initialization" do |app|
        app.middleware.use Sequel::Auditer::Middleware
      end
      attr_accessor :env
    end
  end
end
