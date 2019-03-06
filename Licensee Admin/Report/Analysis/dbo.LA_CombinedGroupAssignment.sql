USE [bodb_licensee]
GO

/****** Object:  Table [dbo].[LA_CombinedGroupAssignment]    Script Date: 3/6/2019 5:12:35 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[LA_CombinedGroupAssignment](
	[GroupId] [smallint] NOT NULL,
	[PartyId] [int] NOT NULL,
	[GroupType] [tinyint] NOT NULL,
 CONSTRAINT [PK_LA_CombinedGroupAssignment] PRIMARY KEY CLUSTERED 
(
	[GroupId] ASC,
	[PartyId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


