variable_source "data" "file/csv" {
  file              = "test-data.csv"
  fields            = ["title", "description"]
  ignore_first_line = false
  delimiter         = ","
}

request "todos_list" {
  method  = "GET"
  uri = "/api/todos/"
  headers = {
    Content-Type  = "application/json"
    Useragent     = "load-generator"
  }
}

request "todos_new" {
  method  = "POST"
  uri = "/api/todos/"
  headers = {
    Content-Type  = "application/json"
    Useragent     = "load-generator"
  }
  preprocessor {
    mapping = {
      t = "source.data[rand].title"
      d = "source.data[rand].description"
    }
  }
  body = <<-EOF
    {"title": "{{ .request.todos_new.preprocessor.t }}", "description": "{{ .request.todos_new.preprocessor.d }}", "completed": false}
  EOF
  postprocessor "var/jsonpath" {
    mapping = {
      id = "$.id"
    }
  }
}

request "todos_get" {
  method  = "GET"
  uri = "/api/todos/{{.request.todos_new.postprocessor.id}}/"
  headers = {
    Content-Type  = "application/json"
    Useragent     = "load-generator"
  }
  postprocessor "var/jsonpath" {
    mapping = {
      id = "$.id",
      title = "$.title",
      description = "$.description",
    }
  }
}

request "todos_put" {
  method  = "PUT"
  uri = "/api/todos/{{.request.todos_get.postprocessor.id}}/"
  headers = {
    Content-Type  = "application/json"
    Useragent     = "load-generator"
  }
  body = <<-EOF
    {"id": "{{.request.todos_get.postprocessor.id}}", "title": "{{.request.todos_get.postprocessor.title}}", "description": "{{.request.todos_get.postprocessor.description}}", "completed": true}
  EOF
  postprocessor "var/jsonpath" {
    mapping = {
      id = "$.id",
      title = "$.title",
      description = "$.description",
    }
  }
}

request "todos_delete" {
  method  = "DELETE"
  uri = "/api/todos/{{.request.todos_new.postprocessor.id}}/"
  headers = {
    Content-Type  = "application/json"
    Useragent     = "load-generator"
  }
}

scenario "editor" {
  requests = [
    "todos_new",
    "sleep(100)",
    "todos_get",
    "sleep(100)",
    "todos_put",
    "sleep(100)",
    "todos_delete",
  ]
}

scenario "viewer" {
  requests = [
    "todos_list",
    "sleep(100)",
  ]
}
