Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :document_number, :phone, :name,
  # Partner search (?q=Marcos+Pereira) carries a person's name. Anchored
  # because a bare :q would match every key that merely contains the letter,
  # like request or quantity.
  /\Aq\z/
]

# filter_parameters only redacts the controller's "Parameters: {...}" log
# line, logged at :info. filter_attributes redacts #inspect and #to_json of
# a record carrying these attributes (an exception backtrace, a console
# session), confirmed against a real Catalog::Partner. Neither one redacts
# the INSERT/UPDATE SQL query log line itself: this Postgres adapter logs
# that line with every value already substituted into the printed string,
# not as a separate bind array, so there is nothing left for either filter
# to intercept by the time it is printed. Found by reading a real request's
# log output while verifying this change, not by reasoning about it; see
# docs/security.md's Accepted risks for the actual mitigation (that line
# logs at :debug, which production's default log level never emits).
Rails.application.config.active_record.filter_attributes = [ :document_number, :phone, :name, :email ]
