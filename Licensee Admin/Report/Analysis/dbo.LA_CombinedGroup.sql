USE [bodb_licensee]
GO

/****** Object:  Table [dbo].[LA_CombinedGroup]    Script Date: 3/6/2019 5:12:30 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[LA_CombinedGroup](
	[GroupId] [smallint] IDENTITY(1,1) NOT NULL,
	[GroupName] [varchar](50) NOT NULL,
	[PathCode] [varchar](50) NOT NULL,
 CONSTRAINT [PK_LA_CombinedGroup] PRIMARY KEY CLUSTERED 
(
	[GroupId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


