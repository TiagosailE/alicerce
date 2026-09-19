module Identity
  class UserSerializer
    def initialize(user)
      @user = user
    end

    def as_json
      { id: @user.id, name: @user.name, email: @user.email, demo: @user.demo? }
    end
  end
end
