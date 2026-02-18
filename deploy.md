# Library files
Using `boss` as the example target system:

`cat library.txt | xargs -i scp {}.sh rod@boss:/home/rod/{}.sh`

Then, `ssh boss` and:

`sudo chown root:root fs-*.sh && sudo mv fs-*.sh /usr/local/lib`

# Pogram files
**NOTE**: Change the destination path as needed.

 Using `boss` as the example target system:

`cat program.txt | xargs -i scp {}.sh rod@boss:/home/rod/`

 Then, `ssh boss` and:

`sudo chown root:root fs-*.sh && sudo chmod +x fs-*.sh && for file in fs-*.sh; do sudo mv "$file" "/usr/local/sbin/${file%.sh}"; done`
