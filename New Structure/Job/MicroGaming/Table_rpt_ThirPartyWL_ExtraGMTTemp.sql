USE [bodb_LicenseeReport]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[rpt_ThirPartyWL_ExtraGMTTemp](
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
