use bodb_LicenseeReport
go

CREATE TABLE dbo.rptLicPerformanceAnalysisHeader(
	RecordId	INT IDENTITY(1,1) NOT NULL,
	ReportDate	DATE NOT NULL,
	SiteId		INT NOT NULL,
	ProductId	INT NOT NULL,
	CurrencyId	INT NOT NULL,
	IsBillingCurrency	BIT NOT NULL
	CONSTRAINT PK_rptLicPerformanceAnalysisHeader PRIMARY KEY (RecordId),
	CONSTRAINT [UQ_rptLicPerformanceAnalysisHeader] UNIQUE NONCLUSTERED (ReportDate,SiteId,ProductId,CurrencyId)
)
GO