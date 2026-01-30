@echo off
echo Starting httpdLite Server tests...

echo Running functional test...
python test_html.py

echo Running concurrency stress test...
python test_concurrency.py

echo Running methods stress test...
python test_methods.py

echo Running resources stress test...
python test_resources.py

echo Tests finished.
pause