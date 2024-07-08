/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240709@Danny
	DB: DBCUST.bodb_licensee
	Task: Add new SOAFile table RedmineId #194604
*/
USE bodb_licensee
GO

CREATE TABLE [dbo].[LA_SOAFile](
	[SOAId] [bigint] IDENTITY(1,1) NOT NULL,
	[PartyID] [int] NULL,
	[InvoiceHeaderID] [bigint] NULL,
	[Environment] [varchar](50) NULL,
	[CreatedDate] [datetime] NULL,
	[CreatedBy] [int] NULL,
	[FileData] [varbinary](max) NULL,
	[BillerId] [int] NULL,
	[SOAType] [tinyint] NULL,
	[CurrencyId] [int] NULL,
	[StatementDate] [datetime] NULL,
	[FileName] [nvarchar](255) NULL,
 CONSTRAINT [pk_SOAId] PRIMARY KEY CLUSTERED 
(
	[SOAId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [DATA]
) ON [DATA] TEXTIMAGE_ON [DATA]
GO


