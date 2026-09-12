```text
============================= test session starts ==============================
platform linux -- Python 3.14.2, pytest-9.1.1, pluggy-1.6.0 -- /home/awabi/Desktop/KM Uni Project/.venv/bin/python3
cachedir: .pytest_cache
rootdir: /home/awabi/Desktop/KM Uni Project
configfile: pyproject.toml
plugins: anyio-4.13.0
collecting ... collected 4 items

send_money_psql.py::test_send_money_success PASSED                       [ 25%]
send_money_psql.py::test_send_money_fail PASSED                          [ 50%]
send_money_psql.py::test_negative_balance_fails PASSED                   [ 75%]
send_money_psql.py::test_cannot_send_more_than_available PASSED          [100%]

============================== 4 passed in 0.08s ===============================
```
