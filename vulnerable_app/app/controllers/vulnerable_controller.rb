class VulnerableController < ApplicationController
  def new
  end

  def upload
    uploaded_file = params[:file]
    filename = params[:filename].presence || uploaded_file.original_filename

    save_uploaded_file(uploaded_file, filename)
    render json: { status: "File uploaded successfully!", filename: filename }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def save_uploaded_file(uploaded_file, filename)
    upload_path = Rails.root.join("tmp", "uploads")
    FileUtils.mkdir_p(upload_path)

    # Save the file to the upload directory
    File.open(File.join(upload_path, filename), 'wb') do |file|
      file.write(uploaded_file.read)
    end
  end
end

