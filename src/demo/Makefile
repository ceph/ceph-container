# Copyright 2016 The Rook Authors. All rights reserved.
# Copyright (c) 2017 SUSE LLC
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

# Environment variables required to be set for this Makefile:
#   DEMO_IMAGE - the tag to be applied to the build of the demo image
#                  (e.g., ceph/demo:testbuild1)
#   BUILD_ARGS (optional) - additional arguments to the container build

.PHONY: build push clean

build:
	@echo === docker build $(DEMO_IMAGE)
	@echo running cmd: sleep 30
	@sleep 30
	@echo running cmd: docker images
	@docker images
	@echo running cmd: docker build $(BUILD_ARGS) -t $(DEMO_IMAGE) .
	@docker build $(BUILD_ARGS) -t $(DEMO_IMAGE) .

push: ; @docker push $(DEMO_IMAGE)
clean:
# Don't fail if can't clean; user may have removed the image
	@docker rmi $(DEMO_IMAGE) || true
