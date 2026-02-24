module StudentsHelper
  # View helper to avoid rendering dead `href="#"` placeholders.
  # If the underlying data is missing, render a visually-disabled span instead of a non-functional link.
  def student_contact_button(student, kind)
    base_classes = "btn btn-outline-secondary btn-sm link-button"

    case kind
    when :email
      if student.email.present?
        mail_to student.email,
                "Email",
                class: class_names(base_classes, "available" => true)
      else
        content_tag :span,
                    "Email",
                    class: class_names(base_classes, "missing" => true),
                    aria: { disabled: true }
      end
    when :github
      if student.github_username.present?
        link_to "GitHub",
                "https://github.com/#{student.github_username}",
                class: class_names(base_classes, "available" => true),
                target: "_blank",
                rel: "noopener"
      else
        content_tag :span,
                    "GitHub",
                    class: class_names(base_classes, "missing" => true),
                    aria: { disabled: true }
      end
    else
      raise ArgumentError, "Unknown contact button kind: #{kind.inspect}"
    end
  end

  # UI-only predicate to keep the students table view readable.
  # Preserves legacy behavior: if CanCan isn't available in the view context, show the actions.
  def can_modify_student_row?(student)
    ui_can?(:modify, student)
  end
end
