# shakemap3.5-docker-image
Built images can be found at the DockerHub:
* https://hub.docker.com/r/jrhartog/shakemap3.5/
# Building an image
* Clone this repo to /directory/of/your/choice on your local machine
* Decide on a name, tag, and label (e.g. the ShakeMap svn Revision number)

Inside the /directory/of/your/choice:
* sudo docker build -t image-name:tag -label="Whatever you want" .

if you are part of the docker group you do not need to use sudo.

