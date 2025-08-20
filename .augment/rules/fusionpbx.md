---
type: "manual"
---

- Dự án đang compile build docker image từ hãng fusionpbx.
- Bám sát tài liệu official, tránh việc tự ý tạo config riêng khi không cần thiết.
- Đảm bảo image có thể custom được port và volume khi tái sử dụng.
- Build và push docker-hub với script build-multiarch.sh.
- Test kỹ image đã build với docker-compose.dev và script deploy-dev.sh có sẵn tại thư mục root của dự án, để đảm bảo quá trình deploy được tự động hoàn toàn.
- Triển khai production trên host production với thông tin: ssh root@42.96.20.37.