from datetime import datetime, time
from typing import Any

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, String, Text, Time, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


class AutomationRule(Base):
    __tablename__ = "automation_rules"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    schedule_days: Mapped[list[str]] = mapped_column(JSONB, nullable=False)
    schedule_time: Mapped[time] = mapped_column(Time, nullable=False)
    start_offset_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    period_days: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    statuses: Mapped[list[int]] = mapped_column(JSONB, nullable=False)
    recipients: Mapped[list[str]] = mapped_column(JSONB, nullable=False)
    subject: Mapped[str] = mapped_column(Text, nullable=False)
    text_template: Mapped[str] = mapped_column(Text, nullable=False)
    html_template: Mapped[str] = mapped_column(Text, nullable=False)
    send_when_empty: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    include_leave_type: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    filters: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    updated_by: Mapped[str] = mapped_column(String(320), nullable=False)

    revisions: Mapped[list["AutomationRuleRevision"]] = relationship(
        back_populates="rule", cascade="all, delete-orphan"
    )


class AutomationRuleRevision(Base):
    __tablename__ = "automation_rule_revisions"
    __table_args__ = (UniqueConstraint("rule_id", "version", name="uq_rule_revision_version"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    rule_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("automation_rules.id", ondelete="CASCADE"), nullable=False, index=True
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    snapshot: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    created_by: Mapped[str] = mapped_column(String(320), nullable=False)

    rule: Mapped[AutomationRule] = relationship(back_populates="revisions")

