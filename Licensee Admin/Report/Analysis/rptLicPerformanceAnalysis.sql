use bodb_LicenseeReport
go

CREATE TABLE dbo.rptLicPerformanceAnalysis(
	ReportDate	DATE NOT NULL,
	SiteId		INT NOT NULL,
	ProductId	INT NOT NULL,
	CurrencyId	INT NOT NULL,
	Turnover	MONEY,
	BetCount	INT,
	LicenseeWinloss	MONEY,
	LicensingFee	MONEY,
	Discount		MONEY,
	Rebate			MONEY,
	RebateRate		MONEY,
	CONSTRAINT PK_rptLicPerformanceAnalysis PRIMARY KEY (ReportDate,SiteId,ProductId,CurrencyId)
)
GO