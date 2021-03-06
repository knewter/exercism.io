require 'digest/sha1'

class User
  include Mongoid::Document

  field :u, as: :username, type: String
  field :img, as: :avatar_url, type: String
  field :cur, as: :current, type: Hash, default: {}
  field :comp, as: :completed, type: Hash, default: {}
  field :g_id, as: :github_id, type: Integer
  field :key, type: String, default: ->{ create_key }
  field :j_at, type: Time, default: ->{ Time.now.utc }
  field :adm, as: :is_admin, type: Boolean, default: false

  alias_method :admin?, :is_admin

  has_many :submissions
  has_many :notifications

  def self.from_github(id, username, email, avatar_url)
    user = User.where(github_id: id).first
    user ||= User.create(username: username, github_id: id, email: email, avatar_url: avatar_url)
    if avatar_url && !user.avatar_url
      user.avatar_url = avatar_url.gsub(/\?.+$/, '')
      user.save
    end
    user
  end

  def ongoing
    @ongoing ||= current_exercises.map do |exercise|
      latest_submission_on(exercise) || NullSubmission.new(exercise)
    end
  end

  def done
    @done ||= completed_exercises.map do |lang, exercises|
      exercises.map do |exercise|
        latest_submission_on(exercise) || NullSubmission.new(exercise)
      end
    end.flatten
  end

  def submissions_on(exercise)
    submissions.order_by(at: :desc).where(language: exercise.language, slug: exercise.slug)
  end

  def guest?
    false
  end

  def do!(exercise)
    self.current[exercise.language] = exercise.slug
    save
  end

  def doing?(language)
    current.key?(language)
  end

  def complete!(exercise, options = {})
    trail = options[:on]
    self.completed[exercise.language] ||= []
    self.completed[exercise.language] << exercise.slug
    self.current[exercise.language] = trail.after(exercise, completed[exercise.language]).slug
    save
  end

  def completed?(exercise)
    completed_exercises.any? {|_, exercises| exercises.include?(exercise) }
  end

  def completed_exercises
    unless @completed_exercises
      @completed_exercises = {}
      completed.map do |language, slugs|
        @completed_exercises[language] = slugs.map {|slug| Exercise.new(language, slug)}
      end
    end
    @completed_exercises
  end

  def current_languages
    current.keys
  end

  def current_exercises
    current.to_a.map {|cur| Exercise.new(*cur)}
  end

  def current_on(language)
    current_exercises.find {|ex| ex.language == language}
  end

  def ==(other)
    username == other.username && current == other.current
  end

  def is?(handle)
    username == handle
  end

  def may_nitpick?(exercise)
    admin? || completed?(exercise)
  end

  def nitpicker?
    admin? || completed.size > 0
  end

  def new?
    !admin? && submissions.count == 0
  end

  private

  def latest_submission_on(exercise)
    submissions_on(exercise).first
  end

  def create_key
    Digest::SHA1.hexdigest(secret)
  end

  def secret
    "There is solemn satisfaction in doing the best you can for #{github_id} billion people."
  end
end

