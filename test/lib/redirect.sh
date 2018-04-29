:
# side effects
# * redirect stderr to test.err
# * redirect fd3 to stderr
# * redirect fd4 to /dev/null

# handle internal redirection
exec 2>test.err 3>&2 4>/dev/null

