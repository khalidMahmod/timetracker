class User < ActiveRecord::Base

  has_many :attendances, dependent: :destroy
  has_many :leave, dependent: :destroy
  has_one :leave_tracker, dependent: :destroy

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  devise :omniauthable, :omniauth_providers => [:google_oauth2]

  ADMIN_USER = CONFIG['admins']

  EMPLOYEE = 1
  TTF = 2
  SUPER_TTF = 3

  ROLES = [
      ['Employee', EMPLOYEE],
      ['TTF', TTF],
      ['Super TTF', SUPER_TTF]
  ]


  scope :inactive, -> {where('is_active = ?', false)}
  scope :active, -> {where('is_active = ?', true)}
  scope :ttf, -> {where('role = ?', User::TTF)}
  scope :super_ttf, -> {where('role = ?', User::SUPER_TTF)}
  scope :employees, -> {where('role = ?', User::EMPLOYEE)}
  scope :list_of_ttfs, -> (super_ttf) {where('role = ? AND sttf_id = ? ', User::TTF, super_ttf)}
  scope :list_of_employees, -> (ttf) {where('role =? AND ttf_id = ? ', User::EMPLOYEE, ttf)}

  def is_admin?
    self.email && ADMIN_USER.to_s.include?(self.email)
  end

  def is_employee?
    self.role === User::EMPLOYEE
  end

  def is_ttf?
    self.role === User::TTF
  end

  def is_super_ttf?
    self.role === User::SUPER_TTF
  end

  def self.find_for_google_oauth2(access_token, signed_in_resource=nil)
    data = access_token.info
    user = User.where(:email => data['email']).first

    unless user
      user = User.create(name: data['name'],
                         email: data['email'],
                         password: Devise.friendly_token[0, 20])
    end

    user
  end

  def create_attendance parent
    self.attendances.create(
        :user_id => self.id,
        :checkin_date => Date.today,
        :in_time => Time.now.to_s(:time),
        :parent_id => parent.nil? ? nil : parent.id
    )
  end

  def find_todays_entry
    todays_entry = Attendance.where(:user_id => self.id, :checkin_date => Date.today, :out_time => nil).first
    todays_entry
  end

  def update_first_entry(today = Date.today)
    not_first_entry = self.attendances.where("checkin_date = ? AND is_first_entry = ? ", today, true).count
    if not_first_entry == 0
      todays_first_entry = self.attendances.find_by_checkin_date(today)
      todays_first_entry.update_attribute(:is_first_entry, true)
    end
  end

  def add_hours_for_missing_out(today = Date.today)
    last_office_day = self.attendances.where("checkin_date != ? AND is_first_entry = ? AND attendances.total_hours IS NULL ",
                                             today, true).last
    if last_office_day.present?
      last_office_day.update_attribute(:total_hours, 2)
    end
  end

  def remember_me
    true
  end

  def self.to_csv(options = {})

    CSV.generate(options) do |csv|
      csv << [nil, nil, "#{1.month.ago.strftime('%B')}", nil, nil, "#{2.month.ago.strftime('%B')}", nil, nil, "#{3.month.ago.strftime('%B')}", nil, nil, "#{4.month.ago.strftime('%B')}", nil, nil, "#{5.month.ago.strftime('%B')}", nil, nil, "#{6.month.ago.strftime('%B')}", nil]
      csv << ['User email', 'Total hours', 'Average hours', 'Average in time', 'Total hours', 'Average hours', 'Average in time', 'Total hours', 'Average hours', 'Average in time', 'Total hours', 'Average hours', 'Average in time', 'Total hours', 'Average hours', 'Average in time', 'Total hours', 'Average hours', 'Average in time']

      all.each do |user|

        first_month = user.attendances.monthly_attendance_summary(1.month.ago.at_beginning_of_month, 1.month.ago.end_of_month).includes(:children)
        second_month = user.attendances.monthly_attendance_summary(2.month.ago.at_beginning_of_month, 2.month.ago.end_of_month).includes(:children)
        third_month = user.attendances.monthly_attendance_summary(3.month.ago.at_beginning_of_month, 3.month.ago.end_of_month).includes(:children)
        fourth_month = user.attendances.monthly_attendance_summary(4.month.ago.at_beginning_of_month, 4.month.ago.end_of_month).includes(:children)
        fifth_month = user.attendances.monthly_attendance_summary(5.month.ago.at_beginning_of_month, 5.month.ago.end_of_month).includes(:children)
        sixth_month = user.attendances.monthly_attendance_summary(6.month.ago.at_beginning_of_month, 6.month.ago.end_of_month).includes(:children)

        csv << [
            "#{user.email}",
            "#{Attendance.monthly_total_hours(first_month)}", "#{Attendance.monthly_average_hours(Attendance.monthly_total_hours(first_month), first_month.size)}", "#{Attendance.monthly_average_check_in_time(first_month)}",
            "#{Attendance.monthly_total_hours(second_month)}", "#{Attendance.monthly_average_hours(Attendance.monthly_total_hours(second_month), second_month.size)}", "#{Attendance.monthly_average_check_in_time(second_month)}",
            "#{Attendance.monthly_total_hours(third_month)}", "#{Attendance.monthly_average_hours(Attendance.monthly_total_hours(third_month), third_month.size)}", "#{Attendance.monthly_average_check_in_time(third_month)}",
            "#{Attendance.monthly_total_hours(fourth_month)}", "#{Attendance.monthly_average_hours(Attendance.monthly_total_hours(fourth_month), fourth_month.size)}", "#{Attendance.monthly_average_check_in_time(fourth_month)}",
            "#{Attendance.monthly_total_hours(fifth_month)}", "#{Attendance.monthly_average_hours(Attendance.monthly_total_hours(fifth_month), fifth_month.size)}", "#{Attendance.monthly_average_check_in_time(fifth_month)}",
            "#{Attendance.monthly_total_hours(fourth_month)}", "#{Attendance.monthly_average_hours(Attendance.monthly_total_hours(fifth_month), sixth_month.size)}", "#{Attendance.monthly_average_check_in_time(sixth_month)}"]
      end
    end
  end

  def self.create_unannounced_leave
    User.all.each do |u|
      unless u.find_todays_entry.present?
        unless u.has_applied_for_leave
          leave = u.leave.create ({
              :user_id => u.id,
              :leave_type => Leave::UNANNOUNCED,
              :start_date => Time.now,
              :status => Leave::ACCEPTED
          })
          leave.update_leave_tracker
          UserMailer.send_unannounced_leave_notification(leave).deliver
        end
      end
    end
  end

  def has_applied_for_leave
    one_day_leave = self.leave.where('start_date = ? AND status = ?', Time.now.to_date, Leave::ACCEPTED).first
    multiple_days_leave = self.leave.where('start_date <= ? AND end_date >= ? AND status =?', Time.now.to_date, Time.now.to_date, Leave::ACCEPTED).first

    if one_day_leave || multiple_days_leave
      return true
    end

    return false
  end
end