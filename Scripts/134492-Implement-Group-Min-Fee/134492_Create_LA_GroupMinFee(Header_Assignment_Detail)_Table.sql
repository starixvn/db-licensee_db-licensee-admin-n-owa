/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200602@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Implement-Group-Min-Fee [#FeatureID 134492]
	Description: Scripts regarding creating tables: LA_GroupMinFee (Header, Assignment, and Detail).
*/
USE bodb_Licensee 
GO

-- 001. LA_GroupMinFeeHeader
CREATE TABLE [dbo].[LA_GroupMinFeeHeader](
	[GroupMinFeeID] [smallint] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[Name] [nvarchar](100) NOT NULL,
	[FromDate] [date] NOT NULL,
	[ToDate] [date] NOT NULL,
 CONSTRAINT [PK_LA_GroupMinFeeHeader] PRIMARY KEY CLUSTERED 
(
	[GroupMinFeeID] ASC
)) ON [OWA_DATA]
GO

-- 002. LA_GroupMinFeeAssignment
CREATE TABLE [dbo].[LA_GroupMinFeeAssignment](
	[GroupMinFeeID] [smallint] NOT NULL,
	[PartyID] [int] NOT NULL,
	[IsPrimary] [bit] NOT NULL,
 CONSTRAINT [PK_LA_GroupMinFeeAssignment] PRIMARY KEY CLUSTERED 
(
	[GroupMinFeeID] ASC,
	[PartyID] ASC
))ON [OWA_DATA]
GO

-- 003. LA_GroupMinFeeDetail
CREATE TABLE [dbo].[LA_GroupMinFeeDetail](
	[GroupMinFeeID] [smallint] NOT NULL,
	[ProductID] [int] NOT NULL,
	[CurrencyId] [int] NOT NULL,
	[FromDate] [date] NOT NULL,
	[ToDate] [date] NOT NULL,
	[MinimumFee] [money] NOT NULL,
	[MinimumFeeTerm] [nvarchar](500) NULL,
 CONSTRAINT [PK_LA_GroupMinFeeDetail] PRIMARY KEY CLUSTERED 
(
	[GroupMinFeeID] ASC,
	[ProductID] ASC,
	[CurrencyId] ASC,
	[FromDate] ASC
)) ON [OWA_DATA]
GO