module ApplicationHelper
    # ----------
    # Navigation
    # ----------
    # Keep sidebar/nav markup clean by centralizing active-state logic here.
    #
    # Examples:
    #   nav_link_to("Semesters", semesters_path, active_when: { controller: "semesters" })
    #   nav_link_to("Status", status_page_path, active_when: { controller: "semesters", action: "status" })
    def nav_link_to(label, path, active_when: nil, **options)
        is_active = nav_active?(path, active_when: active_when)

        existing_classes = options[:class].to_s.split
        if is_active
            existing_classes -= %w[text-dark link-dark]
            existing_classes << "text-white"
        end

        options[:class] = [
            existing_classes.join(" "),
            "nav-link",
            ("active" if is_active)
        ].compact.join(" ")

        options["aria-current"] = "page" if is_active

        link_to(label, path, options)
    end

    # Backwards-compatible alias (was previously unused, but safe to keep).
    def active_class(path)
        nav_active?(path) ? "active" : ""
    end

    def nav_active?(path = nil, active_when: nil)
        return true if active_when.is_a?(Proc) && instance_exec(&active_when)

        if active_when.is_a?(Hash)
            controller_ok = !active_when.key?(:controller) || controller_name == active_when[:controller].to_s
            action_ok = !active_when.key?(:action) || action_name == active_when[:action].to_s
            prefix_ok = !active_when.key?(:starts_with) || request.path.start_with?(active_when[:starts_with].to_s)

            return controller_ok && action_ok && prefix_ok
        end

        return false if path.blank?
        current_page?(path)
    end

    # Status is a per-semester page: /semesters/:id/status.
    # When we don't have a "current" semester in session yet, fall back to Semesters.
    def status_page_path
        semester_id = session[:last_viewed_semester_id]
        semester_id.present? ? semester_status_path(semester_id) : semesters_path
    end

    # This method creates a link with `data-id` and `data-fields` attributes.
    # These attributes are used to create new instances of the nested fields through JavaScript.
    def link_to_add_fields(name, f, association)
        # Create a new instance of the associated model
        new_object = f.object.send(association).klass.new
        id = new_object.object_id

        # Generate nested fields for the associated model
        fields = f.fields_for(association, new_object, child_index: id) do |builder|
            render(association.to_s.singularize + "_fields", f: builder)
        end

        # Render a link with data attributes for the new instance
        link_to(name, '#', class: "add_fields btn btn-secondary", data: { id: id, fields: fields.gsub("\n", "") })
    end

    # UI-only convenience helpers
    # -------------------------
    # These are intentionally NOT authorization rules. They only help views decide what to render.
    # We avoid changing controller/model authorization logic per sponsor-ready refactor constraints.

    def staff_user?(user = current_user)
        user.present? && (user.admin? || user.ta?)
    end

    # Safe wrapper around CanCan's `can?` for views that may be rendered without CanCan available.
    # Preserves legacy behavior: if `can?` isn't present, we default to showing the UI.
    def ui_can?(action, subject)
        return true unless respond_to?(:can?)

        can?(action, subject)
    end
end
