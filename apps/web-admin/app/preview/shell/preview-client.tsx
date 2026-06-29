"use client";

import { useState } from "react";
import { ShieldCheck, Star, UserPlus, Wifi } from "lucide-react";

import { AuthProvider } from "@/components/auth-provider";
import { Sidebar } from "@/components/shell/sidebar";
import { Topbar } from "@/components/shell/topbar";
import {
  Avatar,
  Badge,
  Button,
  Chip,
  Field,
  Input,
  KpiCard,
  KpiGrid,
  Modal,
  Panel,
  PanelBody,
  PanelHead,
  SearchField,
  Tab,
  Table,
  Tabs,
  Td,
  Th,
  Toggle,
  Tr,
} from "@/components/ui";

const SAMPLE_USER = {
  user_id: "00000000-0000-0000-0000-000000000000",
  role: "admin",
  roles: ["admin"],
} as const;

// Static dot classes (a `bg-status-${x}` template literal would escape Tailwind's scanner).
const STATUS_DOT = {
  active: "bg-status-active",
  working: "bg-status-working",
  offline: "bg-status-offline",
} as const;

const ROWS = [
  { name: "สมชาย ใจดี", sub: "GRD-0384", status: "active", rating: "4.9", tone: "green" },
  { name: "วรรณา รักดี", sub: "GRD-0102", status: "working", rating: "4.7", tone: "amber" },
  { name: "ประยุทธ มั่นคง", sub: "GRD-0217", status: "offline", rating: "4.2", tone: "gray" },
] as const;

/** Sample-data composition of the foundation (shell + every ui/ component). */
export function ShellPreview() {
  const [chip, setChip] = useState(0);
  const [tab, setTab] = useState(0);
  const [toggle, setToggle] = useState(true);
  const [modal, setModal] = useState(false);

  return (
    <AuthProvider user={SAMPLE_USER}>
      <div className="flex h-screen">
        <Sidebar />
        <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <Topbar />
          <main className="min-h-0 flex-1 overflow-y-auto bg-app px-7 pb-[60px] pt-[26px]">
            <div className="mb-[22px]">
              <h2 className="mb-[5px] text-[23px] font-semibold tracking-[-0.01em] text-text-strong">
                Foundation preview
              </h2>
              <p className="text-sm text-muted">
                Shell + tokens + component library, sample data (dev-only route)
              </p>
            </div>

            <KpiGrid>
              <KpiCard icon={<ShieldCheck />} label="Guards" value="384" caption="อนุมัติแล้ว" delta="+12%" />
              <KpiCard icon={<Wifi />} label="Online" value="86" caption="กำลังปฏิบัติงาน" delta="+5%" />
              <KpiCard icon={<UserPlus />} label="Applicants" value="12" caption="รอตรวจสอบ" delta="-3%" deltaDirection="down" />
              <KpiCard icon={<Star />} label="Avg rating" value="4.8" caption="จากรีวิวทั้งหมด" />
            </KpiGrid>

            <div className="mb-4 flex flex-wrap items-center gap-2.5">
              {["ทั้งหมด", "ออนไลน์", "กำลังทำงาน", "ออฟไลน์"].map((label, i) => (
                <Chip key={label} active={chip === i} onClick={() => setChip(i)}>
                  {label}
                </Chip>
              ))}
              <div className="flex-1" />
              <SearchField size="sm" placeholder="ค้นหา…" />
            </div>

            <Tabs>
              <Tab active={tab === 0} count={384} onClick={() => setTab(0)}>
                ทั้งหมด
              </Tab>
              <Tab active={tab === 1} count={12} onClick={() => setTab(1)}>
                รอตรวจสอบ
              </Tab>
            </Tabs>

            <div className="grid grid-cols-[2fr_1fr] gap-[18px]">
              <Panel>
                <PanelHead title="พนักงาน รปภ." sub="3 รายการ (ตัวอย่าง)">
                  <Button size="sm" variant="secondary">
                    ส่งออก
                  </Button>
                  <Button size="sm" onClick={() => setModal(true)}>
                    เพิ่มพนักงาน
                  </Button>
                </PanelHead>
                <Table>
                  <thead>
                    <tr>
                      <Th>เจ้าหน้าที่</Th>
                      <Th>สถานะ</Th>
                      <Th>เรตติ้ง</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {ROWS.map((r) => (
                      <Tr key={r.sub}>
                        <Td>
                          <span className="flex items-center gap-[11px]">
                            <Avatar status={r.status}>{r.name.slice(0, 2)}</Avatar>
                            <span>
                              <span className="block font-semibold text-text-strong">{r.name}</span>
                              <span className="block text-xs text-muted">{r.sub}</span>
                            </span>
                          </span>
                        </Td>
                        <Td>
                          <Badge tone={r.tone} dot={STATUS_DOT[r.status]}>
                            {r.status}
                          </Badge>
                        </Td>
                        <Td className="font-mono text-[13px]">{r.rating}</Td>
                      </Tr>
                    ))}
                  </tbody>
                </Table>
              </Panel>

              <Panel>
                <PanelHead title="ฟอร์ม + คอนโทรล" />
                <PanelBody>
                  <Field label="ชื่อ" required hint="ตามบัตรประชาชน">
                    <Input placeholder="สมชาย ใจดี" />
                  </Field>
                  <Field label="หมายเหตุ" error="กรุณากรอกข้อมูล">
                    <Input error placeholder="error state" />
                  </Field>
                  <div className="mb-4 flex items-center gap-3">
                    <Toggle checked={toggle} onChange={setToggle} aria-label="toggle" />
                    <span className="text-sm text-muted">เปิดการแจ้งเตือน</span>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button>Primary</Button>
                    <Button variant="secondary">Secondary</Button>
                    <Button variant="accent">Accent</Button>
                    <Button variant="ghost">Ghost</Button>
                    <Button variant="danger">Danger</Button>
                  </div>
                </PanelBody>
              </Panel>
            </div>

            <Modal
              open={modal}
              onClose={() => setModal(false)}
              title="เพิ่มพนักงาน"
              footer={
                <>
                  <Button variant="secondary" size="sm" onClick={() => setModal(false)}>
                    ยกเลิก
                  </Button>
                  <Button size="sm" onClick={() => setModal(false)}>
                    บันทึก
                  </Button>
                </>
              }
            >
              <Field label="ชื่อ-นามสกุล" required>
                <Input autoFocus />
              </Field>
            </Modal>
          </main>
        </div>
      </div>
    </AuthProvider>
  );
}
