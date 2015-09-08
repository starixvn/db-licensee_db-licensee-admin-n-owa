USE [bodb_LicenseeReport]
GO

IF NOT EXISTS (SELECT 1 FROM sys.filegroups WHERE name = 'rpt_ThirdPartyWL_ExtraGMTData')
BEGIN
	ALTER DATABASE bodb_LicenseeReport
	ADD FILEGROUP rpt_ThirdPartyWL_ExtraGMTData
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_files WHERE name = 'rpt_ThirdPartyWL_ExtraGMT')
ALTER DATABASE bodb_LicenseeReport
ADD FILE
(
	name = rpt_ThirdPartyWL_ExtraGMT,
	filename = 'D:\IBC_DB\bodb_licenseereport\rpt_ThirdPartyWL_ExtraGMT.ndf',
	size = 3072KB,
	maxsize = unlimited,
	filegrowth = 1024KB 
) TO FILEGROUP rpt_ThirdPartyWL_ExtraGMTData;
GO
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'rpt_ThirdPartyWL_ExtraGMT')
BEGIN
	CREATE TABLE [dbo].[rpt_ThirdPartyWL_ExtraGMT](
		[RptDate] [date] NOT NULL,
		[RptDate3rd] [date] NOT NULL,
		[SiteId] [int] NOT NULL,
		[BetTypeId] [int] NOT NULL,
		[CurrencyId] [int] NOT NULL,
		[StatusId] [int] NOT NULL,
		[BetCount] [int] NOT NULL,
		[Turnover] [money] NOT NULL,
		[Winloss] [money] NOT NULL,
		[AComm] [money] NOT NULL,
		[PComm] [money] NOT NULL
	) ON rpt_ThirdPartyWL_ExtraGMTData
	
	CREATE CLUSTERED INDEX [CIX_Winlossdate] ON [dbo].[rpt_ThirdPartyWL_ExtraGMT]
	(
		[RptDate] ASC,
		[RptDate3rd] ASC,
		[SiteId] ASC,
		[BetTypeId] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON rpt_ThirdPartyWL_ExtraGMTData
	

END

GO
GRANT SELECT ON [dbo].[rpt_ThirdPartyWL_ExtraGMT] TO [bodbLicenseeNet] AS [dbo]
GO
GRANT SELECT ON [dbo].[rpt_ThirdPartyWL_ExtraGMT] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[rpt_ThirdPartyWL_ExtraGMT] TO [vnteam] AS [dbo]
GO

