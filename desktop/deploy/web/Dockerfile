# harness.autonomous.ai's browser app as static files, for the existing ArgoCD rollout.
#
# The build context is the directory prepare.py writes — site/ and nginx.conf — not this repo:
#   python3 desktop/deploy/web/prepare.py harness-web-release.json harness-web-X.Y.Z.tar.gz ctx
#   docker build -f desktop/deploy/web/Dockerfile -t harness-web ctx
# so the image serves the exact, checksum-verified bytes of the GitHub release. Non-root, port 8080.
FROM nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
