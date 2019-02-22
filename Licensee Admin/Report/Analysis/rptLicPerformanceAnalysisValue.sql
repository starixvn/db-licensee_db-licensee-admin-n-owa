use bodb_LicenseeReport
go

CREATE TABLE dbo.rptLicPerformanceAnalysisValue(
	RecordId	INT NOT NULL,
	AttributeId	INT NOT NULL,
	Value0		INT,
	Value1		MONEY,
	CONSTRAINT PK_rptLicPerformanceAnalysisValue PRIMARY KEY (RecordId,AttributeId)
)
GO