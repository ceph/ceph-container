# Copyright 2016 The Rook Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.PHONY: build push clean

build:
	@echo === docker build $(DAEMON_BASE_IMAGE)
	@sed -i.makebkp -e 's|MAKEFILE_REPLACE_WITH_BASE_IMAGE|$(BASE_IMAGE)|' Dockerfile
	@docker build $(BUILD_ARGS) -t $(DAEMON_BASE_IMAGE) .


push: ; @docker push $(DAEMON_BASE_IMAGE)
clean:
	# Don't fail if can't clean; user may have removed the image
	docker rmi $(DAEMON_BASE_IMAGE) || true
