use bodb_LicenseeReport
go

CREATE TABLE dbo.rptLicPerformanceAnalysisAttribute(
	AttributeId		INT IDENTITY(1,1) NOT NULL,
	AttributeName	VARCHAR(50) NOT NULL,
	AttributeType	TINYINT NOT NULL,
	CONSTRAINT PK_rptLicPerformanceAnalysisAttribute PRIMARY KEY (AttributeId)
)
GO