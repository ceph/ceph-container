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
#   DAEMON_BASE_IMAGE - the tag to be applied to the build of the daemon-base image
#                       (e.g., ceph/daemon-base:testbuild1)
#   BUILD_ARGS (optional) - additional arguments to the container build

.PHONY: build push clean

build:
	@echo === docker build $(DAEMON_BASE_IMAGE)
	@docker build --pull $(BUILD_ARGS) --tag $(DAEMON_BASE_IMAGE) .

push: ; @docker push $(DAEMON_BASE_IMAGE)
clean:
# Don't fail if can't clean; user may have removed the image
	@docker rmi $(DAEMON_BASE_IMAGE) || true
