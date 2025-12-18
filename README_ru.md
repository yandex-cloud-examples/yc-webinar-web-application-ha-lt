## Пример пайплайна для тестирования на отказоустойчивость

**Данное решение применимо только в Yandex Cloud.**
### Начало работы

> Проверьте доступные квоты на ресурсы.</br>
> Количество требуемых ресурсов рассчитано на основе начальных квот по умолчанию для нового (пустого) облака.

В таблице ниже представлены необходимые квоты.

|Квота|Значение|
|-----|-----|
|Количество облачных сетей|2|
|Количество групп безопасности|7|
|Количество всех публичных IP-адресов|2|
|Количество статических публичных IP-адресов|1|
|Количество подсетей|8|
|Количество дисков|9|
|Количество vCPU виртуальных машин|25|
|Общий объём RAM виртуальных машин|50 GB|
|Количество виртуальных машин|8| 
|Общий объём SSD-дисков|170 GB|
|Общий объём нереплицируемых SSD-дисков|465 GB|
|Количество групп виртуальных машин|3|

### Подготовка инфраструктуры

1.  Делегируйте DNS-домен Yandex Cloud. Поддерживаются домены второго и третьего уровня.

    Для домена второго уровня делегирование выполняется через регистратора доменов.
    Домен третьего уровня делегируется через DNS-хостинг.
    В DNS-зоне (например, `example.com`) создайте две NS-записи следующего вида:

    ```
    playground.example.com.           3600    IN      NS      ns1.yandexcloud.net.
    playground.example.com.           3600    IN      NS      ns2.yandexcloud.net.
    ```

1.  [Установите Yandex Cloud CLI](https://yandex.cloud/en/docs/cli/quickstart) и настройте доступ к облаку с помощью следующей команды:

    ```
    yc init
    ```

1.  В облаке создайте пустой каталог для экспериментов и получите его идентификатор (`folder_id`).
1.  [Создайте новый](https://yandex.cloud/en/docs/managed-gitlab/quickstart) или подключите уже существующий экземпляр GitLab.
1.  В GitLab создайте новый пустой проект и получите его идентификатор (в разделе **Project overview** на странице проекта).
1.  [Создайте токен доступа к проекту](https://docs.gitlab.com/ee/user/project/settings/project_access_tokens.html) с ролью `Maintainer` и областью действия `api`, обеспечивающий полный доступ к API проекта для выполнения операций чтения и записи.
1.  [Установите Terraform и настройте доступ к облаку](https://yandex.cloud/en/docs/tutorials/infrastructure-management/terraform-quickstart). 
1.  Склонируйте репозиторий.
1.  Перейдите в поддиректорию `boostrap`.
1.  Создайте файл переменных Terraform `terraform.tfvars` в поддиректории `boostrap` со следующим содержимым: 

    ```
    folder_id             = "b1gxxxxxxxxxxx"                              # your folder_id here
    dns_domain            = "playground.example.com"                      # your domain here
    dns_hostnames         = ["test1"]                                     # subdomain name here
    gitlab_runner_enabled = true
    gitlab_url            = "https://xxxxxxx.gitlab.yandexcloud.net"      # your GitLab instance URL
    gitlab_project_id     = "0000"                                        # your GitLab project id
    gitlab_username       = "your-username"                               # your GitLab username
    gitlab_access_token   = "glpat-xxxxxxxxxx"                            # your GitLab project access token
    ```

1.  Подготовьте окружение:

    ```
    export YC_TOKEN=$(yc iam create-token)
    ``` 

1.  Выполните следующие команды: 

    ```
    terraform init
    terraform apply
    ``` 

    Проверьте план и подтвердите создание. В рамках этого шага создается начальная инфраструктура, включающая DNS, Container Registry и GitLab Runner, а также выполняется настройка репозитория с добавлением необходимых переменных CI/CD и регистрацией GitLab Runner.

### Запуск тестов

1.  Перейдите в корневую директорию нового репозитория.
1.  Настройте удаленный отслеживаемый репозиторий с помощью следующей команды (обязательно укажите URL вашего репозитория):

    ```
    git remote set-url origin git@xxxxxxx.gitlab.yandexcloud.net:new/repo/location.git
    ```

1.  Вставьте следующий код в GitLab: 

    ```
    git add .
    git commit -m "Initial commit"
    git push --set-upstream origin master
    ```

1.  Перейдите в раздел `build` на странице проекта GitLab и проследите за выполнением пайплайна.
1.  Проверьте результаты в логе задания и на странице мониторинга ALB.
1.  Убедитесь, что задача очистки выполнена успешно. Если нет, запустите ее еще раз.

### Удаление созданных ресурсов

1.  Убедитесь в успешном завершении шага очистки.
1.  Откройте веб-консоль Yandex Cloud. В каталоге `testing` перейдите в раздел **Container Registry** и удалите все образы из реестра контейнеров.
1.  В директории `bootstrap` выполните команду `terraform destroy`, проверьте план и подтвердите удаление.
