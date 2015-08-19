USE [bodb_LicenseeReport]
GO

/****** Object:  Table [dbo].[rpt_ThirPartyWL_ExtraGMT]    Script Date: 12/08/2015 09:43:58 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[rpt_ThirPartyWL_ExtraGMT](
	[RptDate] [date] NOT NULL,
	[RptDate3rd] [date] NOT NULL,
	[SiteId] [int] NOT NULL,
	[BetTypeId] [int] NOT NULL,
	[CurrencyId] [int] NULL,
	[StatusId] [int] NOT NULL,
	[BetCount] [int] NOT NULL,
	[Turnover] [money] NOT NULL,
	[Winloss] [money] NOT NULL,
	[AComm] [money] NOT NULL,
	[PComm] [money] NOT NULL
) 

GO


USE [bodb_LicenseeReport]
GO

/****** Object:  Index [CIX_Winlossdate]    Script Date: 12/08/2015 09:44:06 AM ******/
CREATE CLUSTERED INDEX [CIX_Winlossdate] ON [dbo].[rpt_ThirPartyWL_ExtraGMT]
(
	[RptDate] ASC,
	[RptDate3rd] ASC,
	[SiteId] ASC,
	[BetTypeId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) 
GO


