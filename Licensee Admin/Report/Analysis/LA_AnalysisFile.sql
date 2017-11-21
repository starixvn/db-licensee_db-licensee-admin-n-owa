USE [bodb_licensee]
GO

/****** Object:  Table [dbo].[LA_AnalysisFile]    Script Date: 11/8/2017 12:40:48 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[LA_AnalysisFile](
	[FileId] [int] IDENTITY(1,1) NOT NULL,
	[PartyIds] [varchar](4000) NOT NULL,
	[ProductCodes] [varchar](200) NOT NULL,
	[Filename] [varchar](200) NOT NULL,
	[FromDate] [datetime] NOT NULL,
	[ToDate] [datetime] NOT NULL,
	[Status] [tinyint] NOT NULL, -- 0 - Existed, 1 - Pending, 2 - Processing, 3 - Done
	[IsSkinView] [bit] NOT NULL,
 CONSTRAINT [PK_FileId] PRIMARY KEY CLUSTERED 
(
	[FileId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [OWA_DATA]
) ON [OWA_DATA]
GO

