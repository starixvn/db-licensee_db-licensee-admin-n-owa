/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231212@Danny
	DB: DB052-bodb_Licensee
	Task: Create table for UAT testing

*/
USE bodb_LicenseeReport
GO

SET NOCOUNT ON 
SET ANSI_WARNINGS OFF

IF OBJECT_ID (N'dbo.rptLicPerformanceAnalysis_regen_UAT', N'U') IS NULL  
BEGIN
	CREATE TABLE rptLicPerformanceAnalysis_regen_UAT -- drop later when testing done
	(
		[RecordId] [int] IDENTITY(1,1) NOT NULL,
		[ReportDate] [date] NOT NULL,
		[SiteId] [int] NOT NULL,
		[ProductId] [int] NOT NULL,
		[CurrencyId] [int] NOT NULL,
		[Turnover] [money] NULL,
		[BetCount] [int] NULL,
		[LicenseeWinloss] [money] NULL,
		[LicensingFee] [money] NULL,
		[Discount] [money] NULL,
		[Rebate] [money] NULL,
		[TurnoverNoDraw] [money] NULL,
		[IsBillingCurrency] [bit] NOT NULL,
		[Adjustment] [money] NULL
	)

	CREATE UNIQUE NONCLUSTERED INDEX [IX_rptLicPerformanceAnalysis_regen_UAT] ON [dbo].[rptLicPerformanceAnalysis_regen_UAT]
	(
		[ReportDate] ASC,
		[SiteId] ASC,
		[ProductId] ASC,
		[CurrencyId] ASC
	)
END
