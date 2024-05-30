/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240325@Danny
	DB: DBCUST.bodb_licensee
	Task: Add new Payment table RedmineId #193656
*/
USE bodb_licensee
GO

CREATE TABLE [dbo].[LA_Allocation](
	[AllocationID] [bigint] IDENTITY(1,1) NOT NULL,
	[FromDocumentId] [bigint] NULL,
	[FromDocumentTypeID] [tinyint] NULL,
	[FromBeforeAppliedAmount] [money] NULL,
	[FromAppliedAmount] [money] NULL,
	[FromAfterAppliedAmount] [money] NULL,
	[ToDocumentId] [bigint] NULL,
	[ToDocumentTypeID] [tinyint] NULL,
	[ToBeforeAppliedAmount] [money] NULL,
	[ToAppliedAmount] [money] NULL,
	[ToAfterAppliedAmount] [money] NULL,
	[CreatedDate] [datetime] NULL,
	[CreatedBy] [int] NULL,
	[UpdatedDate] [datetime] NULL,
	[UpdatedBy] [int] NULL,
	[Environment] [varchar](10) NULL,
	[PartyID] [int] NULL,
	CONSTRAINT PK_AllocationID PRIMARY KEY CLUSTERED (AllocationID)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [DATA]
) ON [DATA]





